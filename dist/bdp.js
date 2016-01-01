// Generated by CoffeeScript 1.10.0
(function() {
  var API, LoginError, RESTError, checkStatusCode, request, time, tough, vm,
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  vm = require('vm');

  request = require('request');

  tough = require('tough-cookie');

  time = function() {
    return Math.floor(Date.now() / 1000);
  };

  checkStatusCode = function(res, cb) {
    if (res.statusCode === 200) {
      return true;
    } else {
      cb(new Error("Status Code Error: " + res.statusCode));
      return false;
    }
  };

  LoginError = (function(superClass) {
    extend(LoginError, superClass);

    function LoginError(errno, codeString1, body1) {
      this.errno = errno;
      this.codeString = codeString1 != null ? codeString1 : null;
      this.body = body1 != null ? body1 : null;
      LoginError.__super__.constructor.apply(this, arguments);
      this.name = "LoginError";
      Error.captureStackTrace(this, this.constructor);
    }

    return LoginError;

  })(Error);

  RESTError = (function(superClass) {
    extend(RESTError, superClass);

    function RESTError(api, errno, result) {
      this.api = api;
      this.errno = errno;
      this.result = result;
      RESTError.__super__.constructor.apply(this, arguments);
      this.name = "RESTError";
      Error.captureStackTrace(this, this.constructor);
    }

    return RESTError;

  })(Error);

  API = (function() {
    function API(cookieStr) {
      var c, i, len, ref;
      this.jar = request.jar();
      if (cookieStr) {
        ref = (function() {
          var j, len, ref, results;
          ref = JSON.parse(cookieStr);
          results = [];
          for (j = 0, len = ref.length; j < len; j++) {
            c = ref[j];
            results.push(tough.Cookie.fromJSON(c));
          }
          return results;
        })();
        for (i = 0, len = ref.length; i < len; i++) {
          c = ref[i];
          this.jar.setCookie(c, "http://baidu.com");
        }
      }
      this.r = request.defaults({
        jar: this.jar
      });
    }

    API.prototype.getCookieStr = function() {
      var c;
      return JSON.stringify((function() {
        var i, len, ref, results;
        ref = this.jar.getCookies("http://baidu.com");
        results = [];
        for (i = 0, len = ref.length; i < len; i++) {
          c = ref[i];
          results.push(c.toJSON());
        }
        return results;
      }).call(this));
    };

    API.prototype.refreshToken = function(cb) {
      var url;
      url = "https://passport.baidu.com/v2/api/?getapi&tpl=mn&apiver=v3&class=login&t=" + (time()) + "&logintype=dialogLogin";
      return this.r.get(url, (function(_this) {
        return function(err, res, body) {
          var data;
          if (err) {
            return cb(err);
          }
          if (!checkStatusCode(res, cb)) {
            return;
          }
          if (err) {
            return cb(err);
          }
          data = JSON.parse(body.replace(/'/g, '"'));
          _this.token = data['data']['token'];
          return cb(null);
        };
      })(this));
    };

    API.prototype.checkLogin = function(username, cb) {
      return this.r.get("https://passport.baidu.com/v2/api/?logincheck&token=" + this.token + "&tpl=mn&t=" + (time()) + "&username=" + username, function(err, res, body) {
        var ret, sandbox;
        if (err) {
          return cb(err);
        }
        if (!checkStatusCode(res, cb)) {
          return;
        }
        sandbox = {
          callback: function(data) {
            return data;
          }
        };
        ret = vm.runInNewContext(body, sandbox);
        if (ret.errno === 0) {
          return cb(null, ret.codeString);
        } else {
          return cb(new RESTError('CHECK_LOGIN', ret.errno, ret));
        }
      });
    };

    API.prototype.login = function(username, password, codeString, captcha, cb) {
      var data;
      data = {
        staticpage: 'http://pan.baidu.com/res/static/thirdparty/pass_v3_jump.html',
        charset: 'utf-8',
        token: this.token,
        tpl: 'mn',
        apiver: 'v3',
        tt: time().toString(),
        codestring: codeString,
        safeflg: '0',
        u: 'http://pan.baidu.com/',
        isPhone: 'false',
        quick_user: '0',
        logintype: 'basicLogin',
        username: username,
        password: password,
        verifycode: captcha,
        mem_pass: 'on',
        ppui_logintime: '57495',
        callback: 'parent.bd__pcbs__ax1ysj'
      };
      return this.r.post('https://passport.baidu.com/v2/api/?login', {
        form: data
      }, (function(_this) {
        return function(err, res, body) {
          var _, errNo, ref;
          if (err) {
            return cb(err);
          }
          if (!checkStatusCode(res, cb)) {
            return;
          }
          ref = body.match(/err_no=(\d+).+codeString=([\w\d]*)/), _ = ref[0], errNo = ref[1], codeString = ref[2];
          errNo = parseInt(errNo);
          switch (errNo) {
            case 0:
              return cb(null);
            case 6:
            case 257:
              return cb(new LoginError(errNo, codeString));
            default:
              return cb(new LoginError(errNo, null, body));
          }
        };
      })(this));
    };

    API.prototype.getVerifyImageUrl = function(codeString) {
      return "https://passport.baidu.com/cgi-bin/genimage?" + codeString;
    };

    API.prototype.getUK = function(cb) {
      return this.r.get('http://pan.baidu.com/disk/home', function(err, res, body) {
        var m, uk;
        if (err) {
          return cb(err);
        }
        if (!checkStatusCode(res, cb)) {
          return;
        }
        m = body.match(/MYUK\s*=\s*"([\d]+)"/);
        if (!m) {
          m = body.match(/yunData.+"uk":([\d]+)/);
        }
        uk = parseInt(m[1]);
        return cb(null, uk);
      });
    };

    API.prototype._req = function(uri, opt, cb) {
      var k, qs, ref, url, v;
      if (typeof uri === 'object') {
        cb = opt;
        opt = uri;
      }
      if (typeof opt === 'function') {
        cb = opt;
        opt = {};
      }
      url = opt['url'] ? opt['url'] : "http://pan.baidu.com/api/" + uri;
      qs = {
        app_id: "250528",
        web: '1',
        clienttype: '0',
        channel: 'chunlei',
        t: time().toString(),
        bdstoken: this.token
      };
      if (opt['qs']) {
        ref = opt['qs'];
        for (k in ref) {
          v = ref[k];
          qs[k] = v;
        }
      }
      if (opt['form']) {
        return this.r.post(url, {
          qs: qs,
          form: opt['form']
        }, cb);
      } else {
        return this.r.get(url, {
          qs: qs
        }, cb);
      }
    };

    API.prototype.getFileMeta = function(path, cb) {
      var form, qs;
      qs = {
        blocks: 1,
        dlink: 1
      };
      form = {
        target: JSON.stringify([path])
      };
      return this._req('filemetas', {
        form: form
      }, function(err, res, body) {
        var ret;
        if (err) {
          return cb(err);
        }
        if (!checkStatusCode(res, cb)) {
          return;
        }
        ret = JSON.parse(body);
        switch (ret.errno) {
          case 0:
            return cb(null, ret['info'][0]);
          case 12:
            return cb(null, null);
          default:
            return cb(new RESTError('FILE_META', ret.errno, ret));
        }
      });
    };

    API.prototype.share = function(fid, pwd, cb) {
      var form;
      if (typeof pwd === 'function') {
        cb = pwd;
        pwd = null;
      }
      form = {
        fid_list: JSON.stringify([fid]),
        schannel: 4,
        channel_list: '[]'
      };
      if ((pwd != null) && pwd.length === 4) {
        form['pwd'] = pwd;
      }
      return this._req({
        url: 'http://pan.baidu.com/share/set',
        form: form
      }, function(err, res, body) {
        var ret;
        if (err) {
          return cb(err);
        }
        if (!checkStatusCode(res, cb)) {
          return;
        }
        ret = JSON.parse(body);
        ret['uk'] = ret['link'].match(/uk=(\d+)/)[1];
        if (ret.errno === 0) {
          return cb(null, ret);
        } else {
          return cb(new RESTError('SHARE', ret.errno, ret));
        }
      });
    };

    API.prototype.transfer = function(shareid, uk, pwd, path, destPath, cb) {
      var _transfer, form, qs;
      _transfer = (function(_this) {
        return function() {
          var form, qs;
          qs = {
            shareid: shareid,
            from: uk
          };
          form = {
            filelist: JSON.stringify([path]),
            path: destPath
          };
          return _this._req({
            url: 'http://pan.baidu.com/share/transfer',
            qs: qs,
            form: form
          }, function(err, res, body) {
            var ret;
            if (err) {
              return cb(err);
            }
            if (!checkStatusCode(res, cb)) {
              return;
            }
            ret = JSON.parse(body);
            switch (ret.errno) {
              case 0:
                return cb(null);
              default:
                return cb(new RESTError('TRANSFER', ret.errno, ret));
            }
          });
        };
      })(this);
      if (pwd === '') {
        return _transfer();
      } else {
        qs = {
          shareid: shareid,
          uk: uk
        };
        form = {
          pwd: pwd,
          vcode: ''
        };
        return this._req({
          url: 'http://pan.baidu.com/share/verify',
          qs: qs,
          form: form
        }, function(err, res, body) {
          var ret;
          if (err) {
            return cb(err);
          }
          if (!checkStatusCode(res, cb)) {
            return;
          }
          ret = JSON.parse(body);
          switch (ret.errno) {
            case 0:
              return _transfer();
            default:
              return cb(new RESTError('VERIFY', ret.errno, ret));
          }
        });
      }
    };

    API.prototype.getQuota = function(cb) {
      return this._req("quota", function(err, res, body) {
        var ret;
        if (err) {
          return cb(err);
        }
        if (!checkStatusCode(res, cb)) {
          return;
        }
        ret = JSON.parse(body);
        if (ret.errno === 0) {
          return cb(null, ret['used'], ret['total']);
        } else {
          return cb(new RESTError('QUOTA', ret.errno, ret));
        }
      });
    };

    return API;

  })();

  module.exports = function(cookie) {
    return new API(cookie);
  };

}).call(this);
