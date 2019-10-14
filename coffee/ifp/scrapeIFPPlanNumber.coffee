###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
async = require 'async'
linecount = require 'linecount'
Horseman = require "node-horseman"

startedPageUrl = 'https://apply.coveredca.com/apspahbx/ahbxanonym.portal?_nfpb=true&_st=&_nfls=false&_pageLabel=previewPlanPage#'

FILE_CREATED_THRESHOLD = new Date "2017-11-23T10:00:00.000Z"

module.exports = scrapeHealthCarePlanNumber = (census, cb) ->
	{zip, annualIncome, numOfHousehold, ageOfHead, county, ifpRegionCode} = census
	countyNames = []

	# start point
	console.log "#{zip} >> Zipcode:", zip
	console.log "#{zip} >> Region Code:", ifpRegionCode
	console.log "#{zip} >> County Name:", county.name if county?.name?

	zipTimer = Date.now()
	stepTimer = Date.now()
	root = "resource/out/ifp/CA/#{ifpRegionCode}"
	outputFileName = "#{root}/#{zip}.csv"
	if county?
		countyUri = county.name.replace /\s/g, "-"
		countyUri = countyUri.toLowerCase()
		outputFileName = "#{root}/#{zip}-#{countyUri}.csv"

	unless fs.existsSync outputFileName
		console.log "#{zip} >> ZipCode is NOT loaded"
		return cb null,
			done: false

	fileStat = fs.statSync outputFileName
	fileCreated = new Date fileStat.birthtime
	if fileCreated <= FILE_CREATED_THRESHOLD
		console.log "#{zip} >> #{fileCreated}"
		return cb null,
			done: true

	linecount outputFileName, (err, count) ->
		if err?
			console.error err
			return cb null,
				done: false

		loadedPlanNumber = count - 1
		console.log "#{zip} >> Existing loaded plan number is #{loadedPlanNumber}"

		completed = false
		horseman = new Horseman
			timeout : 30000
			loadImages : false
			switchToNewTab : true
			webSecurity: true
			ignoreSSLErrors: true

		done = ->
			completed = true # indicate completed so the regular scraping doesn't callback
			horseman.close()

		scrapeTimeOut = setTimeout ->
			return if completed
			console.log "#{zip} >> Timeout !!! Process next location ..."
			done()
			cb null,
				done: false
		, 30*1000 # 30s time out to process next location

		clearScrapeTimeout = ->
			clearTimeout scrapeTimeOut # shut down the timeout watcher

		# horseman
		# 	.on 'error', (msg, trace) ->
		# 		console.log "#{zip} >> Error occurred for #{zip}"
		# 		console.log msg
		# 		console.log trace
		# 		return if msg? and msg is "TypeError: null is not an object (evaluating 'data.total_hits')"
		# 		console.log "#{zip} >> Process next location ..."
		# 		done()
		# 		cb null,
		# 			done: false
		# 	.on 'timeout', (timeout) ->
		# 		console.log "#{zip} >> Timeout occurred for #{zip}"
		# 		console.log "#{zip} >> Process next location ..."
		# 		done()
		# 		cb null,
		# 			done: false

		stepTimer = Date.now() - stepTimer
		console.log "#{zip} >> Initialization took #{stepTimer}ms"
		stepTimer = Date.now()
		horseman
			.open startedPageUrl
			.wait 1000
			.catch (err) ->
				console.error err
				console.log "#{zip} >> Failed to open the started page"
				clearScrapeTimeout()
				done()
				cb null,
					done: false
			.waitFor (selector) ->
				return $(selector).length > 0
			, 'select#previewplancoverageyear', true
			.value 'select#previewplancoverageyear'
			.then (year) ->
				console.log "#{zip} >> Working on plan year #{year}"
				stepTimer = Date.now() - stepTimer
				console.log "#{zip} >> Open first page took #{stepTimer}ms"
				stepTimer = Date.now()
			.type 'input#zipcode', zip
			# type another entry to trigger the focus lost event of zip
			.type 'input#annual', annualIncome
			.wait 1000
			# .screenshot("ifp-census-#{zip}.png")
			.evaluate (selector) ->
				return $(selector).parent().is(":visible")
			, "div.ui-dialog div#zipCode-popup"
			.then (hasZipInvalidPopup) ->
				if hasZipInvalidPopup
					console.log "#{zip} >> Zip Code #{zip} is not in Service Area"
					console.log "#{zip} >> Process next location ..."
					done()
					return cb null,
						done: true
						countyNames: countyNames
				else
					horseman
						.select 'select#numOfHousehold', numOfHousehold
						.wait 1000
						.type 'input#agehead', ageOfHead
						.type 'input.float-left', ageOfHead
						.exists 'select#countyId'
						.then (hasMoreCounty) ->
							if hasMoreCounty
								console.log "#{zip} >> There are more counties in the zipcodes"
								unless county?
									horseman
										.evaluate (selector) ->
											counties = []
											$(selector).each ->
												counties.push
													value: $(@).val()
													name: $(@).text()
											return counties
										, 'select#countyId option:not(:first-child)'
										.then (counties) ->
											countyNames = counties
								else
									horseman
										.log "#{zip} >> Select county : #{county.name}"
										.select 'select#countyId', county.value
						.log "#{zip} >> Typing census done"
						.click 'input#continueLink'
						.wait 2000
						# .screenshot('ifp-census-1.png')
						.click 'button[title=\'Continue\']'
						.log "#{zip} >> Click Continue button"
						.wait 2000
						.waitForNextPage()
						.catch (err) ->
							console.error err
							console.log "#{zip} >> Failed to Click Continue button"
						# .screenshot('ifp-census-2.png')
						.click 'a[title=\'Preview Plans\']'
						.log "#{zip} >> Click Preview Plans button"
						.waitForNextPage()
						.catch (err) ->
							console.error err
							console.log "#{zip} >> Failed to Click Preview Plans button"
							clearScrapeTimeout()
							done()
							cb null,
								done: false
						# .screenshot('ifp-census-3.png')
						.switchToFrame 'myframe'
						.click 'input[title=\'SKIP\']'
						.log "#{zip} >> Click SKIP button to skip prescription drug question"
						.wait 2000
						# .screenshot('ifp-census-4.png')
						.switchToFrame 'myframe'
						.click 'input[title=\'SKIP\']'
						.log "#{zip} >> Click SKIP button to skip doctor search"
						.waitForNextPage()
						.catch (err) ->
							console.error err
							console.log "#{zip} >> Failed to open the quote page"
						# .screenshot('ifp-census-5.png')
						.switchToFrame 'myframe'
						# .waitForSelector 'a.view-detail'
						.waitFor (selector) ->
							return $(selector).length > 1
						, 'a.view-detail', true
						# .screenshot('ifp-quote-1.png')
						.html 'span#filteredPlanCount'
						.then (html) ->
							totalPlanSize = parseInt html
							console.log "#{zip} >> Total plans number : #{totalPlanSize}"
							stepTimer = Date.now() - stepTimer
							console.log "#{zip} >> Landing on quote page took #{stepTimer}ms"
							done()
							clearScrapeTimeout()
							zipTimer = Date.now() - zipTimer
							console.log "#{zip} >> Zipcode #{zip} took #{zipTimer}ms"

							if loadedPlanNumber isnt totalPlanSize
								console.log "#{zip} >> Loaded plan number is NOT matched online plan number !!!"
								fs.unlinkSync outputFileName if fs.existsSync outputFileName
							else
								console.log "#{zip} >> All loaded !!!"

							cb null,
								done: true
								countyNames: countyNames

if process.argv[1] and process.argv[1].match(__filename)
	census =
		zip: '92877'
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'
		ifpRegionCode: '17'

	scrapeHealthCarePlanNumber census, (err) ->
		console.log err if err?
		console.log "#{census.zip} >> Done"
		process.exit 0
