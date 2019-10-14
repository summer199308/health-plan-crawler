fs = require 'fs'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'
{dataScraper, ALL_ERRORS} = require './scrapeIFPDataV4'

NUM_PHANTOMJS_INSTANCE = process.env.NUM_PHANTOMJS || 3
NUM_PHANTOMJS_INSTANCE = parseInt NUM_PHANTOMJS_INSTANCE

LAUNCH_TIMES = process.env.LAUNCH_TIMES || 1
LAUNCH_TIMES = parseInt LAUNCH_TIMES

zipcodes = []

stream = csv.createCsvFileReader 'resource/in/zip-CA.csv'
loadTask = (task, nextRow) ->
	{data} = task

	zipcodes.push
		zip: data[0]
		county: data[1]
		ifpRegionCode: data[2]
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'
		_id: _.uniqueId()

	setImmediate nextRow

process.on 'unhandledRejection', (err) ->
	console.error err, "unhandledRejection watcher"
	# process.exit 1

process.on 'uncaughtException', (err) ->
	console.error err, "uncaughtException watcher"
	# process.exit 1

# setTimeout ->
# 	console.log process.memoryUsage(), "Memory Usage"
# , 10000

zipsNotInServiceArea = []
countiesNotMatched = []
zipsWithErrorOccurred = []

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total ZipCode - #{zipcodes.length}"
	async.timesSeries LAUNCH_TIMES, (times, nextTime) ->
		console.warn "LANUCH #{times+1} TIMES" if LAUNCH_TIMES > 1
		async.eachLimit zipcodes, NUM_PHANTOMJS_INSTANCE, (zip, next) ->
			return next() if _.includes zipsNotInServiceArea, zip.zip
			console.log "#{zip.zip} >> Start Scrape IFP Data - #{zip.zip}"
			dataScraper zip, (err) ->
				if err?.message is ALL_ERRORS.ZipCodeNotInServiceArea
					zipsNotInServiceArea.push zip.zip
				else if err?.message is ALL_ERRORS.CountyNotMatched
					countiesNotMatched.push zip
				else if err?
					zipsWithErrorOccurred.push zip
				next()
		, nextTime
	, (err) ->
		console.error err if err?
		console.log 'Donnnnnnnnne'
		if zipsNotInServiceArea.length > 0
			zipsNotInServiceAreaCount = 0
			for zipcode in zipcodes
				zipsNotInServiceAreaCount++ if _.includes zipsNotInServiceArea, zipcode.zip
			console.log 'Zip Codes not in Service Area:', zipsNotInServiceAreaCount
			console.log JSON.stringify(zipsNotInServiceArea)
		if countiesNotMatched.length > 0
			countiesNotMatched = _.uniqBy countiesNotMatched, '_id'
			console.log 'Counties not matched with API result:', countiesNotMatched.length
			countiesNotMatched = _.map countiesNotMatched, (zip) -> "#{zip.zip}, #{zip.county}"
			console.log JSON.stringify(countiesNotMatched)
		if zipsWithErrorOccurred.length > 0
			console.log 'Zip Codes with error occurred:', zipsWithErrorOccurred.length
			console.log JSON.stringify(zipsWithErrorOccurred)
		process.exit 0
