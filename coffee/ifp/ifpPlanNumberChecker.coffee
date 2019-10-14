fs = require 'fs'
fse = require 'fs-extra'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'
dataScraper = require './scrapeIFPPlanNumber'

zipcodes = []
completedList = []

PLAN_DONE_LIST_FILE = "resource/out/ifp/CA/done.json"
doneList = []
if fs.existsSync PLAN_DONE_LIST_FILE
	doneList = fs.readFileSync PLAN_DONE_LIST_FILE, 'utf-8'
	doneList = JSON.parse doneList

# console.log "Done list"
# console.log doneList

stream = csv.createCsvFileReader 'resource/in/zip-CA.csv'
loadTask = (task, nextRow) ->
	{data} = task

	return setImmediate nextRow unless data[1] is '9'
	return setImmediate nextRow if data[0] in doneList

	zipcodes.push
		zip : data[0]
		ifpRegionCode: data[1]
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'

	setImmediate nextRow

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total ZipCode - #{zipcodes.length}"
	async.eachLimit zipcodes, 3, (zip, nextZipCode) ->
		# console.log "#{zip.zip} >> Start Scrape IFP Data"
		completed = false
		dataScraper zip, (err, result) ->
			console.error err if err?
			if not result?.countyNames? or result.countyNames.length is 0
				completedList.push zip.zip if result.done is true
				return nextZipCode()
			completed = result.done
			async.eachSeries result.countyNames, (county, nextCounty) ->
				console.log "#{zip.zip} >> Start Scrape IFP Data for the specific county - #{county.name}"
				zip.county = county
				dataScraper zip, (err, countyResult) ->
					completed = completed && countyResult.done
					console.error err if err?
					nextCounty()
			, ->
				completedList.push zip.zip if completed is true
				nextZipCode()
	, (err) ->
		console.log completedList
		if completedList? and completedList.length > 0
			updatedDoneList = doneList.concat completedList
			fse.writeJsonSync PLAN_DONE_LIST_FILE, updatedDoneList
			console.log "update done list"
		console.log 'Done'
