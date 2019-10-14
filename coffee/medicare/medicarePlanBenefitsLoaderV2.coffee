fs = require 'fs'
fse = require 'fs-extra'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'
dataScraper = require './scrapePlanDataV4'

NUM_PHANTOMJS_INSTANCE = process.env.NUM_PHANTOMJS || 1

LAUNCH_TIMES = process.env.LAUNCH_TIMES || 1
LAUNCH_TIMES = parseInt LAUNCH_TIMES


plans = []
errorCases = []
notFoundCases = []
notAvailableCases = []
notFoundZipCases = []
PlanNotFoundListJSONFile = 'resource/in/PlanNotFoundList.json'

console.log "Load Plan Not Found List"
PlanNotFoundList = fse.readJsonSync PlanNotFoundListJSONFile
console.log PlanNotFoundList

stream = csv.createCsvFileReader 'resource/in/allplans.csv'
loadTask = (task, nextRow) ->
	{data} = task

	planId = data[0]
	state = data[1] || "ALL"
	root = "resource/out/html/#{state}"
	fs.mkdirSync root unless fs.existsSync root
	outputFileName = "#{root}/#{planId}.html"
	return setImmediate nextRow if fs.existsSync outputFileName

	return setImmediate nextRow if _.some PlanNotFoundList, {'planId': planId, 'state': state}

	plans.push
		planId : data[0]
		state : data[1]

	setImmediate nextRow

# process.on 'unhandledRejection', (err) ->
# 	console.error err, "unhandledRejection watcher"

# process.on 'uncaughtException', (err) ->
# 	console.error err, "uncaughtException watcher"

recordPlanNotFoundList = (plan) ->
	plans = fse.readJsonSync PlanNotFoundListJSONFile
	plans = [] if _.isEmpty plans
	plans.push
		planId: plan.planId
		state: plan.state
	fse.writeJsonSync PlanNotFoundListJSONFile, plans

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total plans - #{plans.length}"
	async.timesSeries LAUNCH_TIMES, (times, nextTime) ->
		console.warn "LANUCH #{times+1} TIMES" if LAUNCH_TIMES > 1
		async.eachLimit plans, NUM_PHANTOMJS_INSTANCE, (plan, next) ->
			dataScraper plan, ->
				return next() unless times+1 is LAUNCH_TIMES
				notFoundCases.push plan if plan.failedAsPlanNotFound
				recordPlanNotFoundList plan if plan.failedAsPlanNotFound
				notAvailableCases.push plan if plan.planNotAvailable
				errorCases.push plan if plan.failedAsError
				notFoundZipCases.push plan if plan.failedAsZipCodeNotFound
				next()
		, nextTime
	, (err) ->
		console.log 'Done'
		writer = fs.createWriteStream 'resource/out/exceptions.txt'

		writer.write "*** Plan Not Found ***\n"
		_.each notFoundCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}\n"
		writer.write "\n"
		writer.write "\n"
		writer.write "*** Plan Not Available ***\n"
		_.each notAvailableCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}\n"
		writer.write "\n"
		writer.write "\n"
		writer.write "*** Plan with error ***\n"
		_.each errorCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}\n"
		writer.write "\n"
		writer.write "\n"
		writer.write "*** Plan with zip not found ***\n"
		_.each notFoundZipCases, (ele) ->
			writer.write "#{ele.planId}, #{ele.state}\n"

		writer.end ->
			process.exit 0
