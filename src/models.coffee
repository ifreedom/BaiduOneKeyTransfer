extendModel = (model) ->
  model.findOne = (cond, cb) ->
    this.find cond, 1, (err, datas) ->
      return cb(err) if err
      cb(null, datas[0])
  model.createOne = (data, cb) ->
    this.create [data], (err, datas) ->
      return cb(err) if err
      cb(null, datas[0])

module.exports = (db, models, next) ->
  Users = db.define 'users',
    username: { type: 'text', size: 200 }
    password: { type: 'text', size: 100 }
    uk: { type: 'integer', unsigned: true, size: 8, unique: true }
    token: { type: 'text', unique: true }
    cookie: { type: 'text', size: 4096 }
  extendModel Users

  SmsVerifys = db.define 'smsverifys',
    authtoken: { type: 'text', size: 500, unique: true }
    password: { type: 'text', size: 100 }
    loginproxy: { type: 'text', size: 500 }
    cookie: { type: 'text', size: 4096 }
  extendModel SmsVerifys

  Shares = db.define 'shares',
    shareid: { type: 'integer', unsigned: true, size: 8 }
    uk: { type: 'integer', unsigned: true, size: 8 }
    pass: { type: 'text', size: 4 }
    path: { type: 'text' }
  extendModel Shares

  db.sync (err) ->
    throw err if err
    models.Users = Users
    models.SmsVerifys = SmsVerifys
    models.Shares = Shares
    next();
