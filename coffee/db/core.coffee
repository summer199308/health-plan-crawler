mongoose = require 'mongoose'
mongoose.Promise = global.Promise # use native promises

mongoUri = process.env.MONGOLAB_URI_CORE_DB || 'mongodb://localhost:27017/core'

connection = mongoose.createConnection mongoUri,
	poolSize: 5
	useNewUrlParser: true
	# useCreateIndex: true
	useUnifiedTopology: true

module.exports.mongoose = mongoose
module.exports.conn = connection
