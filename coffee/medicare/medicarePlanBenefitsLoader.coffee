fs = require 'fs'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require './util/queingStream'
dataScraper = require './scrapePlanData'

NUM_PLANS_SCRAPED = 5
NUM_PHANTOMJS_INSTANCE = process.env.NUM_PHANTOMJS || 3
plans = []
errorCases = []
notFoundCases = []
notAvailableCases = []

stream = csv.createCsvFileReader 'resource/in/allplans.csv'
loadTask = (task, nextRow) ->
	{data} = task

	root = "resource/out/html/#{data[1]}"
	outputFileName = "#{root}/#{data[0]}.html"
	if fs.existsSync outputFileName
		console.log "Plan #{data[0]} was already processed"
		return setImmediate nextRow

	plans.push
		planId : data[0]
		state : data[1]
		zipCode : data[2]

	setImmediate nextRow

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total plans - #{plans.length}"
	async.eachLimit _.chunk(plans, NUM_PLANS_SCRAPED), NUM_PHANTOMJS_INSTANCE, (list, next) ->
		dataScraper list, (err) ->
			console.log err if err?
			plansNotFound = _.filter list, (ele) -> return ele.failedAsPlanNotFound
			notFoundCases = _.concat notFoundCases, plansNotFound
			plansNotAvailable = _.filter list, (ele) -> return ele.planNotAvailable
			notAvailableCases = _.concat notAvailableCases, plansNotAvailable
			plansWithError = _.filter list, (ele) -> return ele.failedAsError
			errorCases = _.concat errorCases, plansWithError
			next()
	, (err) ->
		console.log 'Done'
		writer = fs.createWriteStream 'resource/out/exceptions.txt'

		writer.write "*** Plan Not Found ***\n"
		_.each notFoundCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}, #{ele.zipCode}\n"
		writer.write "\n"
		writer.write "\n"
		writer.write "*** Plan Not Available ***\n"
		_.each notAvailableCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}, #{ele.zipCode}\n"
		writer.write "\n"
		writer.write "\n"
		writer.write "*** Plan with error ***\n"
		_.each errorCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}, #{ele.zipCode}\n"

		writer.end ->
			process.exit 0
