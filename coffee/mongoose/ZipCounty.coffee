{mongoose, conn} = require('../db/core')
Schema = mongoose.Schema

ZipCounty = new Schema
	zip:  String
	county: String
	ifpRegionCode: String
	date:
		type: Date
		default: Date.now
	state: String


###
	Export the registered model
###
model = mongoose.model('ZipCounty', ZipCounty)
exports.model = ZipCounty = conn.model 'ZipCounty'
exports.schema = ZipCounty
