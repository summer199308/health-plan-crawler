fs = require 'fs'
_ = require 'lodash'
csv = require 'ya-csv'
firstline = require 'firstline'

queingStream = require '../util/queingStream'


checkFileShouldExists = (cb) ->
	zipcodes = []

	stream = csv.createCsvFileReader 'resource/in/zip-CA.csv'
	loadTask = (task, nextRow) ->
		{data} = task

		zipcodes.push
			zip: data[0]
			county: data[1]
			ifpRegionCode: data[2]

		setImmediate nextRow

	zip2FileName = (zip) ->
		countyUri = zip.county.replace /\s/g, "-"
		countyUri = countyUri.toLowerCase()
		return "#{zip.zip}-#{countyUri}.csv"

	zip2FilePath = (zip) ->
		return "resource/out/ifp/CA/#{zip.ifpRegionCode}/#{zip2FileName(zip)}"

	queingStream
		stream: stream
		task: loadTask
	, ->
		console.log "Total ZipCode - #{zipcodes.length}"
		zipcodeFiles = _.map zipcodes, zip2FilePath
		# console.log zipcodeFiles

		walker = require('walk').walk "resource/out/ifp/CA"
		walker.on "file", (root, fileStats, next) ->
			if fileStats.name is '.DS_Store'
				return next()

			fileName = "#{root}/#{fileStats.name}"

			# console.log "FileName: #{fileName}"
			shouldBeProcessed = _.some zipcodeFiles, (z) ->
				console.log "ZipCode FileName", z
				z is fileName
			return next() if shouldBeProcessed
			originZipCode = _.find zipcodes, (zip) ->
				name = zip2FileName zip
				return fileStats.name is name
			if originZipCode?
				# console.log originZipCode
				originFilePath = zip2FilePath originZipCode
				console.log "Moving file - exists: #{fileName}, should be #{originFilePath}"
				fs.renameSync fileName, originFilePath
			else
				console.log "Remove #{fileName} as it's NOT exists in in-source file"
				fs.unlinkSync fileName

			next()

		walker.on 'end', ->
			console.log 'Done'
			cb()

checkFieldNameList = (cb) ->
	the1stlines = []

	walker = require('walk').walk "resource/out/ifp/CA"
	walker.on "file", (root, fileStats, next) ->
		if fileStats.name is '.DS_Store'
			return next()

		fileName = "#{root}/#{fileStats.name}"
		the1stline = await firstline fileName
		the1stlines.push the1stline

		next()

	walker.on 'end', ->
		console.log "Total #{the1stlines.length} 1st lines"
		the1stlines = _.uniq the1stlines
		console.log "Then #{the1stlines.length} 1st lines"
		console.log 'Done'
		cb()

progressSync = (cb) ->
	zipcodes = []

	stream = csv.createCsvFileReader 'resource/in/zip-CA.csv'
	loadTask = (task, nextRow) ->
		{data} = task

		zipcodes.push
			zip: data[0]
			county: data[1]
			ifpRegionCode: data[2]

		setImmediate nextRow

	zip2FileName = (zip) ->
		countyUri = zip.county.replace /\s/g, "-"
		countyUri = countyUri.toLowerCase()
		return "#{zip.zip}-#{countyUri}.csv"

	zip2FilePath = (zip) ->
		return "resource/out/ifp/CA/#{zip.ifpRegionCode}/#{zip2FileName(zip)}"

	queingStream
		stream: stream
		task: loadTask
	, ->
		console.log "Total ZipCode - #{zipcodes.length}"
		zipcodeFiles = _.map zipcodes, zip2FilePath
		# console.log zipcodeFiles

		ZipCountyModel = require('../mongoose/ZipCounty').model
		count = 0

		ZipCountyModel.deleteMany {}, (err) ->
			console.error err if err?
			walker = require('walk').walk "resource/out/ifp/CA"
			walker.on "file", (root, fileStats, next) ->
				if fileStats.name is '.DS_Store'
					return next()

				fileName = "#{root}/#{fileStats.name}"
				return next() unless _.indexOf(zipcodeFiles, fileName) > 0
				originZipCode = _.find zipcodes, (zip) ->
					name = zip2FileName zip
					return fileStats.name is name

				console.log originZipCode
				zipCounty = new ZipCountyModel originZipCode
				zipCounty.state = 'D'

				zipCounty.save (err, zc) ->
					count++
					console.error err if err?
					next()

			walker.on 'end', ->
				console.log "Total #{count}"
				console.log 'Done'
				cb()

if process.argv[1] and process.argv[1].match(__filename)

	# checkFileShouldExists ->
	# checkFieldNameList ->
	progressSync ->
		process.exit 0
