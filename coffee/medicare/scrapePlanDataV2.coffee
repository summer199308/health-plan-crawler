###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
_ = require 'lodash'
async = require 'async'
Horseman = require "node-horseman"

startedPageUrl = 'https://www.medicare.gov/find-a-plan/questions/search-by-plan-name-or-plan-id.aspx'

WAIT_TIME = process.env.OPT_WAIT_TIME || 1000
WAIT_TIME = parseInt WAIT_TIME

PROCESS_TIME_OUT = process.env.OPT_TIME_OUT || 1
PROCESS_TIME_OUT = parseInt PROCESS_TIME_OUT

module.exports = scrapeMedicareGovPlanData = (plans, cb) ->
	horseman = new Horseman
		timeout : 120000
		loadImages : false
		switchToNewTab : true
		webSecurity: true
		ignoreSSLErrors: true
		phantomOptions:
			# 'debug': 'true'
			'disk-cache': 'true'

	completed = false

	done = ->
		return if completed
		completed = true # indicate completed so the regular scraping doesn't callback
		await horseman.close()

	scrapeTimeOut = setTimeout ->
		return if completed
		console.log "#{PROCESS_TIME_OUT} mins Timeout !!! Process next plan ..."
		console.log plans, "Time out occurred"
		await done()
		cb()
	, PROCESS_TIME_OUT*plans.length*60*WAIT_TIME # X mins time out to process next plan

	clearScrapeTimeout = ->
		clearTimeout scrapeTimeOut # shut down the timeout watcher

	# horseman
	# 	.on 'error', (msg, trace) ->
	# 		console.log 'Error occurred'
	# 		console.log msg, trace
	# 	.on 'timeout', (timeout, msg) ->
	# 		console.log 'Timeout hitted'
	# 		console.log 'Timeout', msg
	# 	.on 'resourceTimeout', (msg) ->
	# 		console.log 'resourceTimeout', msg
	# 	.on 'resourceError', (msg) ->
	# 		console.log 'resourceError', msg
	# 	.on 'loadFinished', (msg) ->
	# 		console.log 'loadFinished', msg
	# 	.on 'loadStarted', (msg) ->
	# 		console.log 'loadStarted', msg

	for plan in plans
		{planId, state} = plan
		state ?= "ALL"
		root = "resource/out/html/#{state}"
		fs.mkdirSync root unless fs.existsSync root
		outputFileName = "#{root}/#{planId}.html"
		if fs.existsSync outputFileName
			plan.processed = true
			console.log "#{planId} >> Plan had been already processed"
			continue

		console.log "#{planId} >> Process starting"

		await horseman.log "#{planId} >> Step 1 - open started page"
		.open startedPageUrl
		.catch (err) ->
			console.error err, "#{planId}", "Failed to open started page"
			plan.failedAsError = true

		continue if plan.failedAsError is true

		await horseman.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$tbPlanID\']', planId
		.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
		.wait WAIT_TIME
		# .screenshot('s1.png')
		.waitForNextPage()
		.catch (err) ->
			console.error err, "#{planId}", "Failed to submit plan ID"
			plan.failedAsError = true

		continue if plan.failedAsError is true

		await horseman.click 'a[title=\'View details for this plan\']'
		.log "#{planId} >> Step 2 - view details"
		.wait 2 * WAIT_TIME
		.waitForNextPage()
		.catch (err) ->
			console.error err, "#{planId}", "Failed to view details page"
			plan.failedAsError = true

		continue if plan.failedAsError is true

		zipCodeSelected = null
		await horseman.click 'a#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_viewZipsLink'
		.wait WAIT_TIME
		.waitForNextPage()
		.catch (err) ->
			console.error err, "#{planId}", "Failed to view zip codes page"
			plan.failedAsError = true

		continue if plan.failedAsError is true

		# .screenshot('s1.png')
		# .switchToTab 1
		# .text "div.planfinder-expanding-rounded-content ul li:eq(5)"
		# .then (value) ->
		# 	zipCodeSelected = values
		await horseman.evaluate (selector) ->
			results = []
			$(selector).each ->
				results.push $(@).text()
			return results
		, 'div.planfinder-expanding-rounded-content ul li'
		.then (results) ->
			zipCodeSelected = _.sample results

		if not /^\d{5}$/.test zipCodeSelected # match zip code regex
			console.log "#{planId} >> Zip code NOT found"
			plan.failedAsZipCodeNotFound = true
			continue

		console.log "#{planId} >> Pick zip code - #{zipCodeSelected}"

		await horseman.closeTab 1
		# .screenshot('out/inner.png')
		.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$txtZipCode\']', zipCodeSelected
		.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
		.wait 2 * WAIT_TIME

		hasMultipleCountiesPopup = false
		await horseman.log "#{planId} >> Check multiple counties"
		.exists 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_0'
		.then (hasPopup) ->
			hasMultipleCountiesPopup = hasPopup

		if hasMultipleCountiesPopup
			console.log "#{planId} >> There is a county list"
			await horseman.click 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_0'
			.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$OkButton\']'
			.wait 2 * WAIT_TIME

		await horseman.log "#{planId} >> Step 3 - go to details page"
		.wait 2 * WAIT_TIME
		.waitForNextPage()
		# .screenshot('out/inner.png')
		.catch (err) ->
			console.error err, "#{planId}", "Failed to go details page"
			plan.failedAsError = true

		continue if plan.failedAsError is true

		await horseman.exists 'div#PlanNameIDSearchError'
		.then (hasError) ->
			return unless hasError
			console.log "#{planId} >> Plan NOT found"
			plan.failedAsPlanNotFound = true

		continue if plan.failedAsPlanNotFound is true

		await horseman.click 'span#__tab_ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel'
		.wait 2 * WAIT_TIME
		# .screenshot('shots/inner.png')
		.html()
		.then (html) ->
			console.log "#{planId} >> Saving html file - #{outputFileName}"
			fs.writeFileSync outputFileName, html
			plan.success = true

		console.log "#{planId} >> Done processing"

	# console.log plans
	clearScrapeTimeout()
	await done()
	cb() if cb?

if process.argv[1] and process.argv[1].match(__filename)
	plans = [
		planId : 'H1951-038-0'
		state : 'LA'
	# ,
	# 	planId : 'H1468-007-0'
	# 	state : 'IL'
	]
	scrapeMedicareGovPlanData plans, ->
		console.log 'Done'
		process.exit()
