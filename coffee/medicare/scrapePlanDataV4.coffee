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

PROCESS_TIME_OUT = process.env.OPT_TIME_OUT || 2
PROCESS_TIME_OUT = parseInt PROCESS_TIME_OUT

module.exports = scrapeMedicareGovPlanData = (plan, cb) ->
	{planId, state} = plan
	state ?= "ALL"
	root = "resource/out/html/#{state}"
	fs.mkdirSync root unless fs.existsSync root
	outputFileName = "#{root}/#{planId}.html"
	if fs.existsSync outputFileName
		plan.processed = true
		console.log "#{planId} >> plan had been already processed"
		return cb()

	horseman = new Horseman
		timeout : 100000
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
		horseman.close()

	scrapeTimeOut = setTimeout ->
		return if completed
		console.log "#{planId} >> #{PROCESS_TIME_OUT} mins Timeout !!! Process next plan ..."
		done()
		cb()
	, PROCESS_TIME_OUT*60*WAIT_TIME # X mins time out to process next plan

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

	console.log "#{planId} >> process starting"

	await horseman.log "#{planId} >> open started page"
	.open startedPageUrl
	.catch (err) ->
		console.error err, "#{planId}", "Failed to open started page"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	await horseman.log "#{planId} >> try to entry plan ID"
	.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$tbPlanID\']', planId
	.log "#{planId} >> click find button"
	.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
	.wait WAIT_TIME
	# .screenshot 'resource/out/inner.png'
	.log "#{planId} >> wait for plan list page"
	.waitForNextPage()
	.catch (err) ->
		console.error err, "#{planId}", "Failed to submit plan ID"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	await horseman.log "#{planId} >> check if there is the view details link"
	.exists 'a[title=\'View details for this plan\']'
	.then (hasViewDetailsLink) ->
		if not hasViewDetailsLink
			console.log "#{planId} >> plan NOT found"
			plan.failedAsPlanNotFound = true

	if plan.failedAsPlanNotFound
		clearScrapeTimeout()
		done()
		return cb()

	await horseman.log "#{planId} >> click view details link"
	.click 'a[title=\'View details for this plan\']'
	.wait WAIT_TIME
	.catch (err) ->
		console.error err, "#{planId}", "Failed to view details page"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	await horseman.log "#{planId} >> wait for the zip code entry page"
	.waitFor (selector) ->
		return $(selector).length > 0
	, 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$txtZipCode\']', true
	# .waitForNextPage()
	.catch (err) ->
		console.error err, "#{planId}", "Failed to view zip code entry page"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	zipCodeSelected = null
	await horseman.log "#{planId} >> click view zip code list link"
	.click 'a#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_viewZipsLink'
	.wait WAIT_TIME
	.log "#{planId} >> wait for zip code list page"
	# .waitForNextPage()
	.log "#{planId} >> done waiting zip code list page"
	.catch (err) ->
		console.error err, "#{planId}", "Failed to view zip codes page"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	# .switchToTab 1
	# .text "div.planfinder-expanding-rounded-content ul li:eq(5)"
	# .then (value) ->
	# 	zipCodeSelected = values
	await horseman.log "#{planId} >> get all zip code values"
	.evaluate (selector) ->
		results = []
		$(selector).each ->
			results.push $(@).text()
		return results
	, 'div#PlanNameIDSearchAvailableZips div.planfinder-expanding-rounded-content ul li'
	.then (results) ->
		zipCodeSelected = _.sample results

	if not /^\d{5}$/.test zipCodeSelected # match zip code regex
		console.log "#{planId} >> zip code NOT found"
		plan.failedAsZipCodeNotFound = true
		clearScrapeTimeout()
		done()
		return cb()

	console.log "#{planId} >> pick zip code - #{zipCodeSelected}"

	await horseman.log "#{planId} >> close zip code page which is a new tab"
	.closeTab 1
	# .click 'a#ctl00_CloseThisPage'
	# .screenshot 'resource/out/inner.png'
	.log "#{planId} >> try to entry zip code"
	.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$txtZipCode\']', zipCodeSelected
	.log "#{planId} >> click find plan button"
	.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
	.wait 2 * WAIT_TIME

	hasMultipleCountiesPopup = false
	await horseman.log "#{planId} >> check multiple counties"
	.exists 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_0'
	.then (hasPopup) ->
		hasMultipleCountiesPopup = hasPopup

	if hasMultipleCountiesPopup
		console.log "#{planId} >> there is a county list"
		await horseman.log "#{planId} >> select the first county"
		.click 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_0'
		.log "#{planId} >> submit selected county"
		.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$OkButton\']'
		.wait 2 * WAIT_TIME

	await horseman.log "#{planId} >> go to details page"
	.wait 2 * WAIT_TIME
	.log "#{planId} >> wait for the plan details page"
	.waitFor (selector) ->
		return $(selector).length > 0
	, 'div#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer', true
	# .waitForNextPage()
	# .screenshot 'resource/out/inner.png'
	# .catch (err) ->
	# 	console.error err, "#{planId}", "Failed to go details page"
	# 	plan.failedAsError = true
	#
	# if plan.failedAsError
	# 	clearScrapeTimeout()
	# 	done()
	# 	return cb()

	await horseman.log "#{planId} >> check if the plan is NOT found"
	.exists 'div#PlanNameIDSearchError'
	.then (hasError) ->
		return unless hasError
		console.log "#{planId} >> plan NOT found with the picked zip code - #{zipCodeSelected}"
		plan.failedAsError = true

	if plan.failedAsError
		clearScrapeTimeout()
		done()
		return cb()

	await horseman.log "#{planId} >> click the details panel"
	.click 'span#__tab_ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel'
	.wait 2 * WAIT_TIME
	# .screenshot('shots/inner.png')
	.html()
	.then (html) ->
		console.log "#{planId} >> saving html file - #{outputFileName}"
		fs.writeFileSync outputFileName, html
		plan.success = true

	console.log "#{planId} >> done processing"

	# console.log plans
	clearScrapeTimeout()
	done()
	cb()

if process.argv[1] and process.argv[1].match(__filename)
	plan =
		planId : 'H5141-037-0'
		state : 'SC'
	scrapeMedicareGovPlanData plan, ->
		console.log 'Done'
		process.exit()
