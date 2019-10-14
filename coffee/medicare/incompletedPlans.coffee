fs = require 'fs'
_ = require 'lodash'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'


allPlans = []

stream = csv.createCsvFileReader 'resource/in/allplans.csv'
loadTask = (task, nextRow) ->
	{data} = task

	allPlans.push
		planId: data[0]
		state: data[1]

	setImmediate nextRow

plan2FilePath = (p) ->
	return "resource/out/html/#{p.state}/#{p.planId}.html"

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total plans - #{allPlans.length}"

	incompletedPlans = []
	for plan in allPlans
		filePath = plan2FilePath plan
		incompletedPlans.push plan unless fs.existsSync filePath

	return unless incompletedPlans.length > 0

	out = fs.createWriteStream "resource/in/allplans-incompleted.csv", flags: 'w'
	writer = new csv.CsvWriter out, {quote: '', escape: ''}
	writer.on 'error', (err) ->
		console.error err
	writer.on 'drain', ->
		console.log "Done writing csv"

	for p in incompletedPlans
		writer.writeRecord [p.planId, p.state]
