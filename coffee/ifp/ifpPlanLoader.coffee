fs = require 'fs'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'
dataScraper = require './scrapeIFPData'

zipcodes = []

stream = csv.createCsvFileReader 'resource/in/zip-CA.csv'
loadTask = (task, nextRow) ->
	{data} = task

	zipcodes.push
		zip : data[0]
		ifpRegionCode: data[1]
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'

	root = "resource/out/ifp/CA/#{zipcodes.ifpRegionCode}"
	outputFileName = "#{root}/#{zipcodes.zip}.csv"
	if fs.existsSync outputFileName
		console.log "File was already processed"
		return setImmediate nextRow

	setImmediate nextRow

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total ZipCode - #{zipcodes.length}"
	async.eachSeries zipcodes, (zip, next) ->
		console.log "Start Scrape IFP Data."
		console.log "Zipcode:", zip.zip
		dataScraper zip, (err, countyNames) ->
			console.log err if err?
			return next() if countyNames?.length is 0
			async.eachSeries countyNames, (county, nextCounty) ->
				console.log "Start Scrape IFP Data for the specific county"
				console.log "Zipcode:", zip.zip
				console.log "County Name:", county.name
				zip.county = county
				dataScraper zip, (err) ->
					console.log err if err?
					nextCounty()
			, next
	, (err) ->
		console.log 'Done'
