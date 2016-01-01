fs = require 'fs'
path = require 'path'
express = require 'express'
cookieParser = require 'cookie-parser'
bodyParser = require 'body-parser'
orm = require 'orm'
uuid = require 'node-uuid'
BDP = require './bdp'
utils = require './utils'

logErr = (err) ->
  utils.inspect err
  console.log err.stack

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

dbPath = ''
if app.get('env') == 'development'
  dbPath = path.resolve 'data.db'
  dbPath = "sqlite://" + dbPath
else
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

router.post "/a/login", (req, res) ->
  utils.inspect req.body
  username = req.body.username
  password = req.body.password
  return res.json err: 'invalid_args' unless username and password

  savePassword = if req.body['save-password']? then password else ''
  codeString = req.body.codeString or ''
  captcha = req.body.captcha or ''

  onLoginEnd = (err, uk) ->
    if err
      if err.name == "LoginError"
        switch err.errno
          when 1, 2, 4, 7
            res.json err: 'other', msg: "帐号或密码有误！"
          when 6, 500002, 500018
            res.json err: 'verify_error', codeString: err.codeString, verifyImgUrl: bdp.getVerifyImageUrl(err.codeString)
          when 3, 257, 200010
            res.json err: 'need_verify', codeString: err.codeString, verifyImgUrl: bdp.getVerifyImageUrl(err.codeString)
          when 5, 16, 17, 120016, 120019, 120021, 400031, 400032, 400034, 500010
            res.json err: 'other', msg: "帐号异常，请前往百度盘检查！"
          else
            res.json err: 'unknown'
      else
        res.json err: 'system_error'
    else
      res.cookie 'uk', uk, signed: true
      res.json err: 'ok'

  bdp = BDP()
  bdp.refreshToken (err) ->
    return onLoginEnd(err) if err
    bdp.login username, password, codeString, captcha, (err) ->
      return onLoginEnd(err) if err
      Users = req.models.Users
      Users.findOne username: username, (err, user) ->
        return onLoginEnd(err) if err
        if user
          user.password = savePassword
          user.cookie = bdp.getCookieStr()
          user.save (err) ->
            onLoginEnd(err, user.uk)
        else
          bdp.getUK (err, uk) ->
            return onLoginEnd(err) if err
            Users.createOne username: username, password: savePassword, uk: uk, cookie: bdp.getCookieStr(), token: uuid.v4(), (err, user) ->
              onLoginEnd(err, uk)

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
      return res.json err: 'system_error' if err
      if share
        doReply share
      else
        bdp = BDP(user.cookie)
        bdp.getFileMeta path, (err, info) ->
          return res.json err: 'unknown' if err
          if info
            pass = utils.genPassword()
            bdp.share info.fs_id, pass, (err, info) ->
              if err
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
      return res.json err: 'system_error' if err
      if share
        if share.uk == user.uk
          share.remove (err) ->
            return res.json err: 'system_error' if err
            res.json err: 'ok'
        else
          res.json err: 'ok'
      else
        res.json err: 'ok'

router.post "/a/transfer", (req, res) ->
  code = req.body.code
  return res.json err: 'invalid_args' unless code

  checkUserLogined req, res, (err, user) ->
    Shares = req.models.Shares
    Shares.findOne id: utils.decodeShareCode(code), (err, share) ->
      return res.json err: 'system_error' if err
      if share
        if share.uk == user.uk
          res.json err: 'other', msg: '请不要转存自己的文件'
        else
          bdp = BDP(user.cookie)
          destPath = '/'
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
                    res.json err: 'unknown'
              else
                res.json err: 'unknown'
            else
              res.json err: 'ok', destPath: destPath
      else
        res.json err: 'file_not_found'

app.use config.root, router

app.listen 8080
console.log 'Running on http://0.0.0.0:8080'
