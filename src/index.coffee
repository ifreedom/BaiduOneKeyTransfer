fs = require 'fs'
express = require 'express'
cookieParser = require 'cookie-parser'
bodyParser = require 'body-parser'
orm = require 'orm'
uuid = require 'node-uuid'
BDP = require './bdp'
utils = require './utils'

logErr = (err) ->
  console.dir err
  console.log err.stack
  console.trace()

config = JSON.parse fs.readFileSync('config.json', 'utf8')

app = express()

app.set('trust proxy', 'loopback')

app.set 'view engine', 'jade'
app.set 'views', __dirname + '/../views'

router = express.Router()

router.use express.static __dirname + '/../public'
router.use express.static __dirname + '/../bower_components'

router.use(cookieParser(config.secret))
router.use(bodyParser.urlencoded(extended: true))

db = config.db
dbPath = "mysql://#{db.username}:#{db.password}@#{db.host}/#{db.database}"
router.use orm.express dbPath,
  define: require './models'

router.use (req, res, next) ->
  res.locals.baseUrl = req.baseUrl
  next()

router.get "/", (req, res) ->
  res.render 'index', page: 'share'

router.get "/transfer/:code", (req, res) ->
  res.render 'index', page: 'transfer'

checkUserLogined = (req, res, cb) ->
  uk = req.signedCookies.uk
  if uk
    Users = req.models.Users
    Users.findOne uk: uk, (err, user) ->
      return res.json err: 'system_error' if err
      if user
        cb(null, user)
      else
        res.json err: 'not_login'
  else
    res.json err: 'not_login'

router.get "/a/checklogin", (req, res) ->
  checkUserLogined req, res, (err, user) ->
    bdp = BDP(user.cookie)
    bdp.getQuota (err) ->
      if err
        if err.name == "RESTError"
          res.json err: 'need_login', username: user.username
        else
          res.json err: 'unknown'
      else
        res.json err: 'ok'

saveUser = (req, bdp, password, cb) ->
  bdp.getUserInfo (err, info) ->
    return cb(err) if err
    Users = req.models.Users
    Users.findOne uk: info.uk, (err, user) ->
      return cb(err) if err
      if user
        user.password = password
        user.cookie = bdp.getCookieStr()
        user.save (err) ->
          cb(err, info.uk)
      else
        Users.createOne username: info.username, password: password, uk: info.uk, cookie: bdp.getCookieStr(), token: uuid.v4(), (err, user) ->
          cb(err, info.uk)

router.post "/a/login", (req, res) ->
  username = req.body.username
  password = req.body.password
  return res.json err: 'invalid_args' unless username and password

  savePassword = if req.body['save-password']? then password else ''
  codeString = req.body.codeString or ''
  captcha = req.body.captcha or ''
  bdp = BDP()

  saveSmsVerify = (token, proxy, cb) ->
    SmsVerifys = req.models.SmsVerifys
    SmsVerifys.findOne authtoken: token, (err, verify) ->
      return cb(err) if err
      if verify
        verify.password = savePassword
        verify.loginproxy = proxy
        verify.cookie = bdp.getCookieStr()
        verify.save (err) ->
          cb(err, verify)
      else
        SmsVerifys.createOne authtoken: token, password: savePassword, loginproxy: proxy, cookie: bdp.getCookieStr(), (err, verify) ->
          cb(err, verify)

  sendSmsVerify = (ret) ->
    bdp.sendSms ret.authtoken, (err) ->
      if err
        if err.name == "RESTError"
          if err.errno == 62003
            res.json err: 'other', msg: "短信发送次数过多"
          else
            res.json err: 'other', msg: err.result.msg
        else
          logErr err
          res.json err: 'system_error'
      else
        saveSmsVerify ret.authtoken, ret.loginproxy, (err, verify) ->
          if err
            logErr err
            res.json err: 'system_error'
          else
            res.json err: 'verify_sms', smsVerifyId: verify.id

  onLoginError = (err) ->
    if err.name == "LoginError"
      ret = err.result
      switch err.errno
        when 1, 2, 4, 7
          res.json err: 'other', msg: "帐号或密码有误！"
        when 6, 500002, 500018
          res.json err: 'verify_error', codeString: ret.codeString, verifyImgUrl: bdp.getVerifyImageUrl(ret.codeString)
        when 3, 257, 200010
          res.json err: 'need_verify', codeString: ret.codeString, verifyImgUrl: bdp.getVerifyImageUrl(ret.codeString)
        when 400031
          sendSmsVerify(ret)
        when 5, 16, 17, 120016, 120019, 120021, 400032, 400034, 500010
          logErr err
          res.json err: 'other', msg: "帐号异常，请前往百度盘检查！"
        else
          logErr err
          res.json err: 'unknown'
    else
      logErr err
      res.json err: 'system_error'

  bdp.refreshToken (err) ->
    if err
      logErr err
      res.json err: 'system_error'
    else
      bdp.login username, password, codeString, captcha, (err) ->
        if err
          onLoginError err
        else
          saveUser req, bdp, savePassword, (err, uk) ->
            if err
              logErr err
              res.json err: 'system_error'
            else
              res.cookie 'uk', uk, signed: true
              res.json err: 'ok'

router.post "/a/smsverify", (req, res) ->
  verifyId = req.body.verifyId
  captcha = req.body.captcha
  return res.json err: 'invalid_args' unless verifyId and captcha

  SmsVerifys = req.models.SmsVerifys
  SmsVerifys.findOne id: verifyId, (err, verify) ->
    bdp = BDP(verify.cookie)
    bdp.checkSmsCode verify.authtoken, captcha, (err) ->
      if err
        if err.name == "RESTError"
          if err.errno == 62004
            res.json err: 'other', msg: '短信验证码错误'
          else if err.errno == 62005
            res.json err: 'other', msg: '短信验证码已失效，请刷新后重试'
          else
            logErr err
            res.json err: 'unknown'
        else
          logErr err
          res.json err: 'system_error'
      else
        bdp.doLoginProxy verify.loginproxy, (err) ->
          if err
            logErr err
            res.json err: 'unknown'
          else
            saveUser req, bdp, verify.password, (err, uk) ->
              if err
                logErr err
                res.json err: 'unknown'
              else
                verify.remove (err) ->
                  if err
                    logErr err
                    res.json err: 'system_error'
                  else
                    res.cookie 'uk', uk, signed: true
                    res.json err: 'ok'

router.post "/a/share", (req, res) ->
  path = req.body.path
  return res.json err: 'invalid_args' unless path

  doReply = (share) ->
    transferCode = utils.encodeShareCode(share.id)
    transferUrl = req.protocol + '://' + req.get('host') + req.baseUrl + '/transfer/' + transferCode
    res.json err: 'ok', transferCode: transferCode, transferUrl: transferUrl

  checkUserLogined req, res, (err, user) ->
    Shares = req.models.Shares
    Shares.findOne uk: user.uk, path: path, (err, share) ->
      if err
        logErr err
        return res.json err: 'system_error'
      if share
        doReply share
      else
        bdp = BDP(user.cookie)
        bdp.getFileMeta path, (err, info) ->
          if err
            logErr err
            return res.json err: 'unknown'
          if info
            pass = utils.genPassword()
            bdp.share info.fs_id, pass, (err, info) ->
              if err
                logErr err
                res.json err: 'unknown'
              else
                Shares.createOne shareid: info.shareid, uk: info.uk, pass: pass, path: path, (err, share) ->
                  return res.json err: 'system_error' if err
                  doReply share
          else
            res.json err: 'file_not_found'

router.post "/a/unshare", (req, res) ->
  code = req.body.code
  return res.json err: 'invalid_args' unless code

  checkUserLogined req, res, (err, user) ->
    Shares = req.models.Shares
    Shares.findOne id: utils.decodeShareCode(code), (err, share) ->
      if err
        logErr err
        return res.json err: 'system_error'
      if share
        if share.uk == user.uk
          share.remove (err) ->
            if err
              logErr err
              return res.json err: 'system_error'
            res.json err: 'ok'
        else
          res.json err: 'ok'
      else
        res.json err: 'ok'

makeTransferDir = (bdp, path, cb) ->
  mkdir = (path, cb) ->
    bdp.getFileMeta path, (err, info) ->
      return cb(err) if err
      return cb(null) if info
      bdp.mkdir path, (err) ->
        return cb(err) if err
        cb(null)

  parts = path.split('/')
  p = parts.shift()
  next = ->
    if parts.length > 0
      p = p + '/' + parts.shift()
      mkdir p, (err) ->
        return cb(err) if err
        next()
    else
      cb(null)
  next()

router.post "/a/transfer", (req, res) ->
  code = req.body.code
  return res.json err: 'invalid_args' unless code

  checkUserLogined req, res, (err, user) ->
    Shares = req.models.Shares
    Shares.findOne id: utils.decodeShareCode(code), (err, share) ->
      if err
        logErr err
        return res.json err: 'system_error'
      if share
        if share.uk == user.uk
          res.json err: 'other', msg: '请不要转存自己的文件'
        else
          bdp = BDP(user.cookie)
          destPath = '/apps/bokt/#{code}'
          makeTransferDir bdp, destPath, (err) ->
            if err
              logErr err
              res.json err: 'unknown'
            else
              bdp.transfer share.shareid, share.uk, share.pass, share.path, destPath, (err) ->
                if err
                  if err.name == "RESTError"
                    switch err.errno
                      when -7, -8, -16, -17
                        # FIXME: auto re-share
                        res.json err: 'other', msg: '分享已失效！'
                      when -32
                        res.json err: 'other', msg: '空间不足！'
                      else
                        logErr err
                        res.json err: 'unknown'
                  else
                    logErr err
                    res.json err: 'unknown'
                else
                  res.json err: 'ok', destPath: destPath
      else
        res.json err: 'file_not_found'

app.use config.root, router

app.listen 8080
console.log 'Running on http://0.0.0.0:8080'
