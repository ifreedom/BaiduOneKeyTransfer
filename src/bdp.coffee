vm = require 'vm'
qs = require 'querystring'
request = require 'request'
tough = require 'tough-cookie'

time = ->
  Math.floor(Date.now() / 1000)

checkStatusCode = (res, cb) ->
  if res.statusCode == 200
    true
  else
    cb(new Error("Status Code Error: #{res.statusCode}"))
    false

class LoginError extends Error
  constructor: (@errno, @result, @body) ->
    super
    @name = "LoginError"
    Error.captureStackTrace(this, @constructor)

class RESTError extends Error
  constructor: (@api, @errno, @result) ->
    super
    @name = "RESTError"
    Error.captureStackTrace(this, @constructor)

class API
  constructor: (cookieStr) ->
    @jar = request.jar()
    if cookieStr
      for c in (tough.Cookie.fromJSON(c) for c in JSON.parse(cookieStr))
        @jar.setCookie(c, "http://baidu.com")
    @r = request.defaults jar: @jar

  getCookieStr: ->
    JSON.stringify((c.toJSON() for c in @jar.getCookies("http://baidu.com")))

  refreshToken: (cb) ->
    url = "https://passport.baidu.com/v2/api/?getapi&tpl=mn&apiver=v3&class=login&t=#{time()}&logintype=dialogLogin"
    @r.get url, (err, res, body) =>
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      data = JSON.parse(body.replace(/'/g, '"'))
      @token = data['data']['token']
      cb(null)

  checkLogin: (username, cb) ->
    @r.get "https://passport.baidu.com/v2/api/?logincheck&token=#{@token}&tpl=mn&t=#{time()}&username=#{username}", (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      sandbox = { callback: (data) -> data }
      ret = vm.runInNewContext body, sandbox
      if ret.errno == 0
        cb(null, ret.codeString)
      else
        cb(new RESTError('CHECK_LOGIN', ret.errno, ret))

  login: (username, password, codeString, captcha, cb) ->
    data =
      staticpage: 'http://pan.baidu.com/res/static/thirdparty/pass_v3_jump.html'
      charset: 'utf-8'
      token: @token
      tpl: 'mn'
      apiver: 'v3'
      tt: time().toString()
      codestring: codeString
      safeflg: '0'
      u: 'http://pan.baidu.com/'
      isPhone: 'false'
      quick_user: '0'
      logintype: 'basicLogin'
      username: username
      password: password
      verifycode: captcha
      mem_pass: 'on'
      ppui_logintime: '57495'
      callback: 'parent.bd__pcbs__ax1ysj'
    @r.post 'https://passport.baidu.com/v2/api/?login', form: data, (err, res, body) =>
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      m = body.match(/href \+= "([^"]+)"/)
      ret = qs.decode m[1]
      errno = parseInt(ret.err_no)
      if errno == 0
        cb(null)
      else
        cb(new LoginError(errno, ret, body))

  getVerifyImageUrl: (codeString) ->
    "https://passport.baidu.com/cgi-bin/genimage?#{codeString}"

  sendSms: (authToken, cb) ->
    qs =
      authtoken: authToken
      type: 'mobile'
      jsonp: '1'
      apiver: 'v3'
      verifychannel: ''
      action: 'send'
      vcode: ''
      questionAndAnswer: ''
      needsid: ''
      rsakey: ''
      countrycode: ''
      subpro: 'netdisk_web'
      callback: 'callback'
    @r.get "http://passport.baidu.com/v2/sapi/authwidgetverify", qs: qs, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      sandbox = { callback: (data) -> data }
      ret = vm.runInNewContext body, sandbox
      if ret.errno == '110000'
        cb(null)
      else
        cb(new RESTError('SEND_SMS', parseInt(ret.errno), ret))

  checkSmsCode: (authToken, captcha, cb) ->
    qs =
      authtoken: authToken
      type: 'mobile'
      jsonp: '1'
      apiver: 'v3'
      verifychannel: ''
      action: 'check'
      vcode: captcha
      questionAndAnswer: ''
      needsid: ''
      rsakey: ''
      countrycode: ''
      subpro: 'netdisk_web'
      callback: 'callback'
    @r.get "http://passport.baidu.com/v2/sapi/authwidgetverify", qs: qs, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      sandbox = { callback: (data) -> data }
      ret = vm.runInNewContext body, sandbox
      if ret.errno == '110000'
        cb(null)
      else
        cb(new RESTError('CHECK_SMS_CODE', parseInt(ret.errno), ret))

  doLoginProxy: (loginProxy, cb) ->
    url = loginProxy + "&apiver=v3&tt=#{time()}&callback=callback"
    @r.get url, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      console.log body
      sandbox = { callback: (data) -> data }
      ret = vm.runInNewContext body, sandbox
      errno = parseInt(ret.errInfo.no)
      if errno == 0
        cb(null)
      else
        cb(new RESTError('DO_LOGIN_PROXY', errno, ret))

  getUserInfo: (cb) ->
    @r.get 'http://pan.baidu.com/share/manage', (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      m = body.match(/MYNAME\s*=\s*"([^"]+)"/)
      username = m[1]
      m = body.match(/MYUK\s*=\s*"([\d]+)"/)
      uk = parseInt(m[1])
      cb(null, username: username, uk: uk)

  _req: (uri, opt, cb) ->
    if typeof(uri) == 'object'
      cb = opt
      opt = uri
    if typeof(opt) == 'function'
      cb = opt
      opt = {}
    url = if opt['url'] then opt['url'] else "http://pan.baidu.com/api/#{uri}"
    qs =
      app_id: "250528"
      web: '1'
      clienttype: '0'
      channel: 'chunlei'
      t: time().toString()
      bdstoken: @token
    if opt['qs']
      for k, v of opt['qs']
        qs[k] = v
    if opt['form']
      @r.post url, qs: qs, form: opt['form'], cb
    else
      @r.get url, qs: qs, cb

  getFileMeta: (path, cb) ->
    qs =
      blocks: 1
      dlink: 1
    form =
      target: JSON.stringify([path])
    this._req 'filemetas', form: form, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      ret = JSON.parse(body)
      switch ret.errno
        when 0
          cb(null, ret['info'][0])
        when 12
          cb(null, null)
        else
          cb(new RESTError('FILE_META', ret.errno, ret))

  mkdir: (path, cb) ->
    qs =
      a: 'commit'
    form =
      path: path
      isdir: '1'
      block_list: '[]'
    this._req "create", qs: qs, form: form, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      ret = JSON.parse(body)
      if ret.errno == 0
        cb(null, ret)
      else
        cb(new RESTError('MKDIR', ret.errno, ret))

  share: (fid, pwd, cb) ->
    if typeof(pwd) == 'function'
      cb = pwd
      pwd = null
    form =
      fid_list: JSON.stringify([fid])
      schannel: 4
      channel_list: '[]'
    form['pwd'] = pwd if pwd? and pwd.length == 4
    this._req url: 'http://pan.baidu.com/share/set', form: form, (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      ret = JSON.parse(body)
      ret['uk'] = ret['link'].match(/uk=(\d+)/)[1]
      if ret.errno == 0
        cb(null, ret)
      else
        cb(new RESTError('SHARE', ret.errno, ret))

  transfer: (shareid, uk, pwd, path, destPath, cb) ->
    _transfer = =>
      qs =
        shareid: shareid
        from: uk
      form =
        filelist: JSON.stringify([path])
        path: destPath
      this._req url: 'http://pan.baidu.com/share/transfer', qs: qs, form: form, (err, res, body) ->
        return cb(err) if err
        return unless checkStatusCode(res, cb)
        ret = JSON.parse(body)
        switch ret.errno
          when 0
            cb(null)
          else
            cb(new RESTError('TRANSFER', ret.errno, ret))

    if pwd == ''
      _transfer()
    else
      qs =
        shareid: shareid
        uk: uk
      form =
        pwd: pwd
        vcode: ''
      this._req url: 'http://pan.baidu.com/share/verify', qs: qs, form: form, (err, res, body) ->
        return cb(err) if err
        return unless checkStatusCode(res, cb)
        ret = JSON.parse(body)
        switch ret.errno
          when 0
            _transfer()
          else
            cb(new RESTError('VERIFY', ret.errno, ret))

  getQuota: (cb) ->
    this._req "quota", (err, res, body) ->
      return cb(err) if err
      return unless checkStatusCode(res, cb)
      ret = JSON.parse(body)
      if ret.errno == 0
        cb(null, ret['used'], ret['total'])
      else
        cb(new RESTError('QUOTA', ret.errno, ret))

module.exports = (cookie)->
  new API(cookie)
