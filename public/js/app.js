$(document).ready(function() {
  var page = $(".card").data("page");
  var apiPrefix;

  if (page == 'share') {
    apiPrefix = window.location.href + 'a/';
  }
  else if (page == 'transfer') {
    var url = window.location.href;
    var pos = url.indexOf('transfer');
    apiPrefix = url.substring(0, pos) + 'a/';
  }

  var checkLogin = function(cb) {
    $.get(apiPrefix + 'checklogin', function(data) {
      var err = data.err;
      if (err == 'ok') {
        cb(null, true);
      }
      else if (err == 'not_login') {
        cb(null, false, '');
      }
      else if (err == 'need_login') {
        cb(null, false, data.username);
      }
    });
  };

  var goPage = function() {
    $(".login").addClass("hidden");

    if (page == "share") {
      $(".share").removeClass("hidden");

      var setErrMsg = function(msg) {
        $(".share .tips").removeClass("hidden").addClass("warning");
        $(".share .tips p").html(msg);
      };

      $(".form-share button").click(function() {
        $("body .mask").removeClass("hidden");

        var path = $(".form-share #path").val();
        if (path.charAt(0) != '/')
          path = '/'+path;

        $.post(apiPrefix+'share', {
          path: path
        }, function(ret) {
          $("body .mask").addClass("hidden");

          var err = ret.err;
          if (err == 'ok') {
            $(".share .tips").removeClass("hidden").removeClass("warning");
            $(".share .tips p").html("转存成功，转存码为"+ret.transferCode+"，转存链接为<a href=\""+ret.transferUrl+"\">"+ret.transferUrl+"</a>");
          }
          else if (err == 'file_not_found') {
            setErrMsg("文件不存在");
          }
          else if (err == 'system_error') {
            setErrMsg("系统错误，请稍候重试");
          }
          else {
            setErrMsg("未知错误，请刷新后重试");
          }
        });
        return false;
      });
      $(".form-unshare button").click(function() {
        $("body .mask").removeClass("hidden");

        $.post(apiPrefix+'unshare', {
          code: $(".form-unshare #transfer-code").val()
        }, function(ret) {
          $("body .mask").addClass("hidden");

          var err = ret.err;
          if (err == 'ok') {
            $(".share .tips").removeClass("hidden").removeClass("warning");
            $(".share .tips p").html("取消转存成功");
          }
          else if (err == 'system_error') {
            setErrMsg("系统错误，请稍候重试");
          }
        });
        return false;
      });
    }
    else if (page == "transfer") {
      var url = window.location.href;
      var pos = url.indexOf('transfer');
      var code = url.substring(pos+9);
      var transfered = false;

      $(".transfer").removeClass("hidden");
      $(".transfer .download-icon").click(function() {
        if (transfered) return false;

        $("body .mask").removeClass("hidden");
        $.post(apiPrefix + 'transfer', { code: code }, function(ret) {
          $("body .mask").addClass("hidden");

          var setErrMsg = function(msg) {
            $(".transfer p").addClass("warning");
            $(".transfer p").text(msg);
          };

          var err = ret.err;
          if (err == 'ok') {
            transfered = true;
            $(".transfer p").removeClass("warning");
            $(".transfer p").text("转存成功");
          }
          else if (err == 'file_not_found') {
            setErrMsg("文件不存在");
          }
          else if (err == 'other') {
            setErrMsg(ret.msg);
          }
          else if (err == 'system_error') {
            setErrMsg("系统错误，请稍候重试");
          }
          else {
            setErrMsg("未知错误，请刷新后重试");
          }
        });
        return false;
      });
    }
  };

  $("body .mask").removeClass("hidden");
  checkLogin(function(err, isLogined, username) {
    $("body .mask").addClass("hidden");

    if (isLogined) {
      goPage();
    }
    else {
      $(".login").removeClass("hidden");
      $(".checkbox input").change(function() {
        if ($(this).is(":checked")) {
          $(this).parent("label").addClass("selected");
          $(".form-login .tips").addClass("warning");
          $(".form-login .tips p").text("请注意密码将会明文保存在服务器上，以便凭证失效时自动取得新的凭证，我们建议您不要保存密码");
        }
        else {
          $(this).parent("label").removeClass("selected");
          $(".form-login .tips").removeClass("warning");
          $(".form-login .tips p").text("请输入您的百度账号和密码");
        }
      });
      $(".form-login #username").val(username);

      $(".form-login button").click(function() {
        $("body .mask").removeClass("hidden");

        $.post(apiPrefix+'login', {
          username: $(".form-login #username").val(),
          password: $(".form-login #password").val(),
          codeString: $(".form-login #code-string").val(),
          captcha: $(".form-login #captcha").val()
        }, function(ret) {
          $("body .mask").addClass("hidden");

          var setErrMsg = function(msg) {
            $(".form-login .tips").addClass("warning");
            $(".form-login .tips p").text(msg);
          };

          var verify = false;
          var setVerify = function(codeString, verifyImgUrl) {
            if (!verify) {
              verify = true;
              $(".form-login .verify-code").removeClass("hidden");
              $(".form-login .verify-code-placeholder").addClass("hidden");
            }
            $(".form-login #code-string").val(codeString);
            $(".form-login .verify-code img").attr("src", verifyImgUrl);
          };

          var err = ret.err;
          if (err == 'ok') {
            goPage();
          }
          else if (err == 'need_verify') {
            setErrMsg("请输入验证码");
            setVerify(ret.codeString, ret.verifyImgUrl);
          }
          else if (err == 'verify_error') {
            setErrMsg("验证码错误");
            setVerify(ret.codeString, ret.verifyImgUrl);
          }
          else if (err == 'file_not_found') {
            setErrMsg("文件不存在");
          }
          else if (err == 'other') {
            setErrMsg(ret.msg);
          }
          else if (err == 'system_error') {
            setErrMsg("系统错误，请稍候重试");
          }
          else {
            setErrMsg("未知错误，请刷新后重试");
          }
        });
        return false;
      });
    }
  });
});