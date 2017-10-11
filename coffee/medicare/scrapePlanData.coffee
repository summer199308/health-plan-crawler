###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
async = require 'async'
Horseman = require "node-horseman"

startedPageUrl = 'https://www.medicare.gov/find-a-plan/questions/search-by-plan-name-or-plan-id.aspx'

module.exports = scrapeMedicareGovPlanData = (plans, cb) ->
	horseman = new Horseman
		timeout : 20000
		loadImages : false
		switchToNewTab : true
		webSecurity: true
		ignoreSSLErrors: true

	horseman
		.on 'error', (msg, trace) ->
			console.log msg, trace
		.on 'timeout', (timeout, msg) ->
			console.log 'timeout', msg
		# .on 'resourceTimeout', (msg) ->
		# 	console.log 'resourceTimeout', msg
		# .on 'resourceError', (msg) ->
		# 	console.log 'resourceError', msg
		# .on 'loadFinished', (msg) ->
		# 	console.log 'loadFinished', msg
		# .on 'loadStarted', (msg) ->
		# 	console.log 'loadStarted', msg

	async.eachSeries plans, (plan, next) ->
		{planId, state} = plan
		state ?= "ALL"
		root = "resource/out/html/#{state}"
		fs.mkdirSync root unless fs.existsSync root
		outputFileName = "#{root}/#{planId}.html"
		if fs.existsSync outputFileName
			plan.processed = true
			console.log "Plan #{planId} was already processed"
			return next()
		console.log "Process plan #{planId}"
		horseman
			.open startedPageUrl
			.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$tbPlanID\']', planId
			.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
			.wait 1000
			.log "Step 1 - #{planId}"
			.waitForNextPage()
			.catch (err) ->
				console.log 'ERROR!!!', err
				plan.failedAsError = true
				next()
			.click 'a[title=\'View details for this plan\']'
			.log "Step 2 - #{planId}"
			.waitForNextPage()
			.catch (err) ->
				console.log 'ERROR!!!', err
				plan.planNotAvailable = true
				next()
			.click 'a#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_viewZipsLink'
			.waitForNextPage()
			# .screenshot('out/inner.png')
			# .switchToTab 1
			.text "div.planfinder-expanding-rounded-content ul li:eq(4)"
			.then (value) ->
				zipCodeSelected = value
				console.log "Pick zip code - #{zipCodeSelected}"
				horseman
					.closeTab 1
					# .screenshot('out/inner.png')
					.type 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$txtZipCode\']', zipCodeSelected
					.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$FindButton\']'
					.wait 1000
			# .do (done) ->
			# 	setTimeout done, 1000
			.log "Step 3 - #{planId}"
			.log "Check multiple counties"
			.exists 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_1'
			.then (hasPopup) ->
				return unless hasPopup
				console.log "There is a county list" if hasPopup
				horseman
					.click 'input#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_countyListButtons_1'
					.click 'input[name=\'ctl00$ctl00$ctl00$MCGMainContentPlaceHolder$ToolContentPlaceHolder$PlanFinderContentPlaceHolder$OkButton\']'
					.wait 1000
			.log "Step 4 - #{planId}"
			.waitForNextPage()
			# .screenshot('out/inner.png')
			.catch (err) ->
				console.log 'ERROR!!!', err
				plan.failedAsError = true
				next()
			.exists 'div#PlanNameIDSearchError'
			.then (hasError) ->
				if hasError
					console.log "Plan NOT found - #{planId}"
					plan.failedAsPlanNotFound = true
					return next()
				horseman
					.click 'span#__tab_ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel'
					.wait 1000
					# .screenshot('shots/inner.png')
					.html()
					.then (html) ->
						# console.log html
						return next() unless html?
						console.log 'Saving html file .'
						plan.success = true
						fs.writeFile outputFileName, html, (err) ->
							console.log err if err?
							console.log "Done processing - #{planId}"
							next()
	, (err) ->
		# console.log plans
		horseman.close()
		cb err if cb?

if process.argv[1] and process.argv[1].match(__filename)
	plans = [
		planId : 'H4627-002-0'
	# ,
	# 	planId : 'H3952-008-0'
	# ,
	# 	planId : 'H3954-156-1'
	# ,
	# 	planId : 'H5577-016-0'
	# ,
	# 	planId : 'H5774-003-0'
	# ,
	# 	planId : 'H4005-001-0'
	# ,
	# 	planId : 'S4802-126-0'
	]
	scrapeMedicareGovPlanData plans, (err) ->
		console.log err if err?
		console.log 'Done'
		process.exit()
