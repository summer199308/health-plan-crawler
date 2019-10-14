###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'
cheerio = require 'cheerio'
request = require 'request'
linecount = require 'linecount'
Horseman = require "node-horseman"

ZipCountyModel = require('../mongoose/ZipCounty').model

WAIT_TIME = process.env.OPT_WAIT_TIME || 1000
WAIT_TIME = parseInt WAIT_TIME
REQUEST_TIME_OUT = process.env.REQUEST_TIME_OUT || 60
REQUEST_TIME_OUT = parseInt REQUEST_TIME_OUT
PROCESS_TIME_OUT = process.env.OPT_TIME_OUT || 5
PROCESS_TIME_OUT = parseInt PROCESS_TIME_OUT

startedPageUrl = 'https://apply.coveredca.com/lw-shopandcompare'
zipCodeApiUrl = 'https://apply.coveredca.com/shopandcompare/zipcounty'

ALL_ERRORS =
	OperationTimeOut: "Operation Time out"
	FailedOpenStartedPage: "Failed open started page"
	ZipCodeNotInServiceArea: "Zip Code is not in Service Area"
	CountyNotMatched: "County is NOT matched with API list"
	FailedClickContinueButton: "Failed Clicking Continue button"
	FailedClickingPreviewButton: "Failed Clicking Preview Plans button"
	FailedOpenQuotePage: "Failed openning quote page"

checkZipCodeAvailable = (zip) ->
	return new Promise (resolve, reject) ->
		request
			url: zipCodeApiUrl
			method: 'POST'
			body:
				year: "2020"
				zip: zip
				counties: []
			json: true
			pool :
				'maxSockets': 100
			timeout: REQUEST_TIME_OUT*1000
			proxy: 'http://127.0.0.1:1087'
		, (err, resp, body) ->
			# console.log resp.statusCode
			# console.log body
			return resolve() if err?
			resolve body

module.exports.dataScraper = scrapeCoveredCAPlanData = (census, cb) ->
	{zip, annualIncome, numOfHousehold, ageOfHead, county, ifpRegionCode} = census

	if _.isEmpty ifpRegionCode
		console.log "#{zip} >> #{zip} doesn't have region code"
		return cb()

	# start point
	root = "resource/out/ifp/CA/#{ifpRegionCode}"
	fs.mkdirSync root unless fs.existsSync root
	# outputFileName = "#{root}/#{zip}.csv"
	countyUri = county.replace /\s/g, "-"
	countyUri = countyUri.toLowerCase()
	outputFileName = "#{root}/#{zip}-#{countyUri}.csv"
	if fs.existsSync outputFileName
		census.processed = true
		console.log "#{zip} >> ZipCode File #{zip} was already processed"
		return cb()

	processedCount = await ZipCountyModel.countDocuments
		zip: zip
		county: county
		ifpRegionCode: ifpRegionCode

	if processedCount > 0
		census.processed = true
		console.log "#{zip} >> ZipCode File #{zip} was already processed via DB counts"
		return cb()

	console.log "#{zip} >> Zipcode: #{zip}, Region Code: #{ifpRegionCode}, County Name: #{county}"

	processedZipCounty = new ZipCountyModel
		zip: zip
		county: county
		ifpRegionCode: ifpRegionCode
		state: 'P'

	processedZipCounty = await processedZipCounty.save()

	zipCodeCheckResult = await checkZipCodeAvailable zip
	# console.log zipCodeCheckResult
	unless zipCodeCheckResult?.counties?.length > 0
		console.log "#{zip} >> Zip Code #{zip} is not in Service Area"
		console.log "#{zip} >> Process next location ..."
		processedZipCounty.state = 'D'
		await processedZipCounty.save()
		return cb new Error ALL_ERRORS.ZipCodeNotInServiceArea

	if zipCodeCheckResult?.counties?.length > 0
		countyExists = _.some zipCodeCheckResult.counties, (c) -> c.countyName.toUpperCase() is county.toUpperCase()
		unless countyExists
			console.log "#{zip} >> Zip Code #{zip} is not in Service Area with incorrect county #{county}"
			console.log "#{zip} >> Process next location ..."
			processedZipCounty.state = 'D'
			await processedZipCounty.save()
			return cb new Error ALL_ERRORS.CountyNotMatched

	completed = false
	horseman = new Horseman
		timeout : REQUEST_TIME_OUT*1000
		loadImages : false
		switchToNewTab : true
		# webSecurity: true
		# ignoreSSLErrors: true
		phantomOptions:
			# 'debug': 'true'
			'disk-cache': 'true'

	done = ->
		return if completed
		completed = true # indicate completed so the regular scraping doesn't callback
		horseman.close()

	scrapeTimeOut = setTimeout ->
		return if completed
		console.log "#{zip} >> #{PROCESS_TIME_OUT} mins Timeout !!! Process next location ..."
		done()
		cb new Error ALL_ERRORS.OperationTimeOut
	, PROCESS_TIME_OUT*60*WAIT_TIME # X mins time out to process next location

	clearScrapeTimeout = ->
		clearTimeout scrapeTimeOut # shut down the timeout watcher

	# horseman.on 'error', (msg, trace) ->
	# 	console.log "#{zip} >> Error occurred for #{zip}"
	# 	console.log msg
	# 	console.log trace
	# 	return if msg? and msg is "TypeError: null is not an object (evaluating 'data.total_hits')"
	# 	console.log "#{zip} >> Process next location ..."
	# 	done()
	# 	cb()
	# horseman.on 'timeout', (timeout) ->
	# 	console.log "#{zip} >> Timeout occurred for #{zip}"
	# 	console.log "#{zip} >> Process next location ..."
	# 	done()
	# 	cb()

	zipTimer = Date.now()
	stepTimer = Date.now()
	await horseman.viewport 1024, 1600
	.open startedPageUrl
	.catch (err) ->
		console.log "#{zip} >> Error occurred while opening start page"
		console.error err
		zipTimer = Date.now() - zipTimer
		console.log "#{zip} >> Error happened after #{zipTimer}ms"
		console.log "#{zip} >> Failed to open the started page initially"
		clearScrapeTimeout()
		done()
		cb new Error ALL_ERRORS.FailedOpenStartedPage
	.waitFor (selector) ->
		return $(selector).length > 0
	, 'input#screeningquestions-enrollyear', true

	await horseman.text 'span#react-select-screeningquestions-enrollyear--value-item'
	.then (year) ->
		console.log "#{zip} >> Working on plan year #{year}"
		stepTimer = Date.now() - stepTimer
		console.log "#{zip} >> Open first page took #{stepTimer}ms"
		stepTimer = Date.now()
	.type 'input#screeningquestions-zip', zip
	# type another entry to trigger the focus lost event of zip
	.type 'input#screeningquestions-householdincomeperyear', annualIncome
	.wait WAIT_TIME*2
	# .screenshot("ifp-census-#{zip}.png")
	.evaluate (selector) ->
		isShowingConfirmModal = $(selector).is(":visible")
		isZipCodeRelated = /^zip\scode/i.test $(selector).find('div.modal-header h2 span').text()
		return isShowingConfirmModal and isZipCodeRelated
	, "div.confirm-modal"
	.then (hasZipInvalidPopup) ->
		if hasZipInvalidPopup
			console.log "#{zip} >> Zip Code #{zip} is not in Service Area"
			console.log "#{zip} >> Process next location ..."
			clearScrapeTimeout()
			done()
			cb new Error ALL_ERRORS.ZipCodeNotInServiceArea

	await horseman.type 'input#screeningquestions-howmanypeopleinhousehold', numOfHousehold
	.keyboardEvent 'keypress', 16777221 # press enter
	# .screenshot("ifp-census-#{zip}.png")
	.wait 2*WAIT_TIME
	.type 'input#screeningquestions-age-0', ageOfHead
	.type 'input#screeningquestions-age-1', ageOfHead
	.exists 'input#screeningquestions-county'
	.then (hasMoreCounty) ->
		if hasMoreCounty
			console.log "#{zip} >> There are more counties in the zipcodes"
			await horseman.log "#{zip} >> Select county : #{county}"
			.type 'input#screeningquestions-county', county
			.keyboardEvent 'keypress', 16777221 # press enter
	.log "#{zip} >> Typing census done"
	.click 'button#account-creation-access-code-invalid-modal-button'
	.wait WAIT_TIME
	.click 'div.confirm-modal button.btn.btn-primary'
	.log "#{zip} >> Click Continue button"
	.wait 3*WAIT_TIME
	# .screenshot('ifp-census-1.png')
	# .waitForNextPage()
	.catch (err) ->
		console.log "#{zip} >> Failed to Click Continue button"
		console.error err
		clearScrapeTimeout()
		done()
		cb new Error ALL_ERRORS.FailedClickContinueButton
	# .screenshot('ifp-census-2.png')
	.click 'button#shopandcompare-previewplans'
	.log "#{zip} >> Click Preview Plans button"
	.waitForNextPage()
	.catch (err) ->
		console.log "#{zip} >> Failed to Click Preview Plans button"
		console.error err
		clearScrapeTimeout()
		done()
		cb new Error ALL_ERRORS.FailedClickingPreviewButton
	# .screenshot('ifp-census-3.png')
	.switchToFrame 'myframe'
	.click 'a#providerSearchNext'
	.log "#{zip} >> Click NEXT button to skip prescription drug question"
	.wait WAIT_TIME
	# .screenshot('ifp-census-4.png')
	.switchToFrame 'myframe'
	.click 'a#medicalUsageNext'
	.log "#{zip} >> Click NEXT button to skip doctor search"
	.wait WAIT_TIME
	.switchToFrame 'myframe'
	.click 'button#prescriptionSubmit'
	.log "#{zip} >> Click VIEW PLANS button to quote page"
	.wait 2*WAIT_TIME
	.catch (err) ->
		console.log "#{zip} >> Failed to open the quote page"
		console.error err
		clearScrapeTimeout()
		done()
		cb new Error ALL_ERRORS.FailedOpenQuotePage
	# .screenshot('ifp-census-5.png')
	.switchToFrame 'myframe'
	.waitFor (selector) ->
		return $(selector).length > 0
	, "div.cp-tile a.detail.gtm_detail", true
	# .screenshot('ifp-quote-1.png')

	totalPlanSize = 0

	plans = []

	await horseman.text 'span#filteredPlanCount'
	.then (html) ->
		totalPlanSize = parseInt html
		console.log "#{zip} >> Total plans number : #{totalPlanSize}"
		stepTimer = Date.now() - stepTimer
		console.log "#{zip} >> Landing on quote page took #{stepTimer}ms"
		stepTimer = Date.now()

	pageCount = Math.ceil(totalPlanSize / 12)

	console.log "#{zip} >> Total page count : #{pageCount}"
	for pageNum in [1..pageCount]
		console.log "#{zip} >> Process plan units on page #{pageNum}"

		getCurrentPage = ->
			cPage = 0
			await horseman.text "div#pagination div.cp-pagination span.cp-pagination__content"
			.then (paginationString) ->
				cPage = paginationString.trim()
				cPage = cPage.slice 0, 1
				cPage = parseInt cPage
			return cPage

		doPagination = ->
			pageNumDiff--
			await horseman.click "div#pagination span.cp-pagination__btn--right a.next"
			.catch (err) ->
				console.log "#{zip} >> Click pagination failed"
			.wait WAIT_TIME/2

		if pageCount > 1 # for multiple pages
			currentPage = await getCurrentPage()
			pageNumDiff = pageNum - currentPage
			if pageNum isnt currentPage
				await doPagination() until pageNumDiff is 0

		detailsLinkIds = []
		# await horseman.screenshot("ifp-quote-#{pageNum}.png")
		await horseman.evaluate (selector) ->
			results = []
			$(selector).each ->
				results.push $(@).attr('id')
			return results
		, 'div.cp-tile a.detail.gtm_detail'
		.then (results) ->
			detailsLinkIds = results
			# console.log detailsLinkIds

		for linkId in detailsLinkIds
			planTimer = Date.now()
			planInfo = {}
			planInfo.zip = zip
			planInfo.ifpRegionCode = ifpRegionCode
			planInfo.details = {}

			if pageCount > 1 # for multiple pages
				currentPage = await getCurrentPage()
				pageNumDiff = pageNum - currentPage
				if pageNum isnt currentPage
					await doPagination() until pageNumDiff is 0

			await horseman.log "#{zip} >> View plan ##{linkId}"
			# .screenshot("ifp-quote-#{linkId}.png")
			.click "a##{linkId}"
			.wait WAIT_TIME/2
			.attribute "div##{linkId} img.cp-tile__img", "alt"
			.then (attr) ->
				console.log "#{zip} >> Carrier:", attr
				planInfo.carrier = attr

			await horseman.text "div.ps-detail__tile div.cp-tile__metal-tier"
			.then (metalTier) ->
				metalTier ?= ''
				metalTier = metalTier.replace(/\s\s+/g, ' ').trim()
				planInfo.planType = metalTier

			await horseman.evaluate (selector) ->
				return $(selector).attr('data-original-title')
			, "div.ps-detail__tile div.cp-tile__plan-name a##{linkId}"
			.then (title) ->
				title ?= ''
				title = title.replace(/\s\s+/g, ' ').trim()
				planName = "#{planInfo.carrier} #{title}"
				console.log "#{zip} >> PlanName:", planName
				planInfo.planName = planName

			await horseman.count "div.ps-detail__highlights a.quality-rating i.icon-star"
			.then (count) ->
				starRating = if count is 0 then "NA" else count.toString()
				# console.log "#{zip} >> StarRating:", starRating
				planInfo.starRating = starRating
			.text "div.ps-detail__tile div.cp-tile__body div.cp-tile__premium span.cp-tile__premium-amount"
			# .text "table.table tbody tr:eq(0) td p"
			.then (text) ->
				premiums = text?.trim().replace("$", "").toString()
				premiums = parseFloat(premiums)/2
				# console.log "#{zip} >> Premiums:", premiums
				premiums = "$#{premiums}"
				planInfo.premiums = premiums
			.html "div#simplifiedDeductibleDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label').text().trim()
				individualAnnualDeductibleAmount = $('div.details p').first()?.text()?.trim().split(" ", 1).toString()
				familyAnnualDeductibleAmount = $('div.details p').last()?.text()?.trim().split(" ", 1).toString()
				planInfo.details[fieldName] = {}
				planInfo.details[fieldName].individual = individualAnnualDeductibleAmount
				planInfo.details[fieldName].family = familyAnnualDeductibleAmount
			.html "div#simplifiedSeparateDrugDeductibleDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label').text().trim()
				individualSeparateDrugDeductibleAmount = $('div.details p').first()?.text()?.trim().split(" ", 1).toString()
				familySeparateDrugDeductibleAmount = $('div.details p').last()?.text()?.trim().split(" ", 1).toString()
				planInfo.details[fieldName] = {}
				planInfo.details[fieldName].individual = individualSeparateDrugDeductibleAmount
				planInfo.details[fieldName].family = familySeparateDrugDeductibleAmount
			.html "div#simplifiedOOPMaxDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label').text().trim()
				individualAnnualOOPLimitAmount = $('div.details p').first()?.text()?.trim().split(" ", 1).toString()
				familyAnnualOOPLimitAmount = $('div.details p').last()?.text()?.trim().split(" ", 1).toString()
				planInfo.details[fieldName] = {}
				planInfo.details[fieldName].individual = individualAnnualOOPLimitAmount
				planInfo.details[fieldName].family = familyAnnualOOPLimitAmount
			.html "div#simplifiedMaxCostPerPrescriptionDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label').text().trim()
				maxCostPerPrescriptionAmount = $('div.details p').first()?.text()?.trim()
				planInfo.details[fieldName] = maxCostPerPrescriptionAmount
			.html "div#doctorVisit1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				primaryCareVisit = $('div.details').first()?.text()?.trim()
				primaryCareVisit = primaryCareVisit.replace('In Network','').trim()
				planInfo.details[fieldName] = primaryCareVisit
			.html "div#doctorVisit2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				specialistVisit = $('div.details').first()?.text()?.trim()
				specialistVisit = specialistVisit.replace('In Network','').trim()
				planInfo.details[fieldName] = specialistVisit
			.html "div#doctorVisit3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				otherPracitionerOfficeVisit = $('div.details').first()?.text()?.trim()
				otherPracitionerOfficeVisit = otherPracitionerOfficeVisit.replace('In Network','').trim()
				planInfo.details[fieldName] = otherPracitionerOfficeVisit
			.html "div#doctorVisit4Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				preventiveCare = $('div.details').first()?.text()?.trim()
				preventiveCare = preventiveCare.replace('In Network','').trim()
				planInfo.details[fieldName] = preventiveCare
			.html "div#test1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				laboratoryTests = $('div.details').first()?.text()?.trim()
				laboratoryTests = laboratoryTests.replace('In Network','').trim()
				planInfo.details[fieldName] = laboratoryTests
			.html "div#test2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				xRayDiagnosticImaging = $('div.details').first()?.text()?.trim()
				xRayDiagnosticImaging = xRayDiagnosticImaging.replace('In Network','').trim()
				planInfo.details[fieldName] = xRayDiagnosticImaging
			.html "div#test3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				otherImaging = $('div.details').first()?.text()?.trim()
				otherImaging = otherImaging.replace('In Network','').trim()
				planInfo.details[fieldName] = otherImaging
			.html "div#drug1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				drugTier1 = $('div.details').first()?.text()?.trim()
				drugTier1 = drugTier1.replace('In Network','').trim()
				planInfo.details[fieldName] = drugTier1
			.html "div#drug2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				drugTier2 = $('div.details').first()?.text()?.trim()
				drugTier2 = drugTier2.replace('In Network','').trim()
				planInfo.details[fieldName] = drugTier2
			.html "div#drug3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				drugTier3 = $('div.details').first()?.text()?.trim()
				drugTier3 = drugTier3.replace('In Network','').trim()
				planInfo.details[fieldName] = drugTier3
			.html "div#drug4Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				drugTier4 = $('div.details').first()?.text()?.trim()
				drugTier4 = drugTier4.replace('In Network','').trim()
				planInfo.details[fieldName] = drugTier4
			.html "div#drug5Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				maxCostPerPrescription = $('div.details p').first()?.text()?.trim()
				planInfo.details[fieldName] = maxCostPerPrescription
			.html "div#outpatient1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				outpatientFacilityFee = $('div.details').first()?.text()?.trim()
				outpatientFacilityFee = outpatientFacilityFee.replace('In Network','').trim()
				planInfo.details[fieldName] = outpatientFacilityFee
			.html "div#outpatient2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				outpatientSurgery = $('div.details').first()?.text()?.trim()
				outpatientSurgery = outpatientSurgery.replace('In Network','').trim()
				planInfo.details[fieldName] = outpatientSurgery
			.html "div#outpatientServicesOfficeVisitsDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				outpatientOfficeVisits = $('div.details').first()?.text()?.trim()
				outpatientOfficeVisits = outpatientOfficeVisits.replace('In Network','').trim()
				planInfo.details[fieldName] = outpatientOfficeVisits
			.html "div#urgent1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				erFacilityFee = $('div.details').first()?.text()?.trim()
				erFacilityFee = erFacilityFee.replace('In Network','').trim()
				planInfo.details[fieldName] = erFacilityFee
			.html "div#urgent2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				erTransportation = $('div.details').first()?.text()?.trim()
				erTransportation = erTransportation.replace('In Network','').trim()
				planInfo.details[fieldName] = erTransportation
			.html "div#urgent3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				urgentCare = $('div.details').first()?.text()?.trim()
				urgentCare = urgentCare.replace('In Network','').trim()
				planInfo.details[fieldName] = urgentCare
			.html "div#urgentProfessionalFeeDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				erProfessionalFee = $('div.details').first()?.text()?.trim()
				erProfessionalFee = erProfessionalFee.replace('In Network','').trim()
				planInfo.details[fieldName] = erProfessionalFee
			.html "div#hospital1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				inpatientHospitalServices = $('div.details').first()?.text()?.trim()
				inpatientHospitalServices = inpatientHospitalServices.replace('In Network','').trim()
				planInfo.details[fieldName] = inpatientHospitalServices
			.html "div#hospital2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				inpatientPhysicianServices = $('div.details').first()?.text()?.trim()
				inpatientPhysicianServices = inpatientPhysicianServices.replace('In Network','').trim()
				planInfo.details[fieldName] = inpatientPhysicianServices
			.html "div#mentalHealth1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				mbhOutpatientServices = $('div.details').first()?.text()?.trim()
				mbhOutpatientServices = mbhOutpatientServices.replace('In Network','').trim()
				planInfo.details[fieldName] = mbhOutpatientServices
			.html "div#mentalHealth2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				mbhInpatientFacilityFee = $('div.details').first()?.text()?.trim()
				mbhInpatientFacilityFee = mbhInpatientFacilityFee.replace('In Network','').trim()
				planInfo.details[fieldName] = mbhInpatientFacilityFee
			.html "div#mentalHealthInpatientProfFeeDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				mbhInpatientProfessionalFee = $('div.details').first()?.text()?.trim()
				mbhInpatientProfessionalFee = mbhInpatientProfessionalFee.replace('In Network','').trim()
				planInfo.details[fieldName] = mbhInpatientProfessionalFee
			.html "div#mentalHealth3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				sudOutpatientServices = $('div.details').first()?.text()?.trim()
				sudOutpatientServices = sudOutpatientServices.replace('In Network','').trim()
				planInfo.details[fieldName] = sudOutpatientServices
			.html "div#mentalHealth4Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				sudInpatientServices = $('div.details').first()?.text()?.trim()
				sudInpatientServices = sudInpatientServices.replace('In Network','').trim()
				planInfo.details[fieldName] = sudInpatientServices
			.html "div#mentalHealthSubDisorderInpProfFeeDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				sudInpatientProfessionalFee = $('div.details').first()?.text()?.trim()
				sudInpatientProfessionalFee = sudInpatientProfessionalFee.replace('In Network','').trim()
				planInfo.details[fieldName] = sudInpatientProfessionalFee
			.html "div#pregnancy1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				prenatalCare = $('div.details').first()?.text()?.trim()
				prenatalCare = prenatalCare.replace('In Network','').trim()
				planInfo.details[fieldName] = prenatalCare
			.html "div#pregnancy2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				dmcInpatientFacilityCare = $('div.details').first()?.text()?.trim()
				dmcInpatientFacilityCare = dmcInpatientFacilityCare.replace('In Network','').trim()
				planInfo.details[fieldName] = dmcInpatientFacilityCare
			.html "div#pregnancyInpatientProfFeeDetail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				dmcInpatientProfessionalFee = $('div.details').first()?.text()?.trim()
				dmcInpatientProfessionalFee = dmcInpatientProfessionalFee.replace('In Network','').trim()
				planInfo.details[fieldName] = dmcInpatientProfessionalFee
			.html "div#specialNeed1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				homeHealthCareServices = $('div.details').first()?.text()?.trim()
				homeHealthCareServices = homeHealthCareServices.replace('In Network','').trim()
				planInfo.details[fieldName] = homeHealthCareServices
			.html "div#specialNeed2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				outpatientRehabilitation = $('div.details').first()?.text()?.trim()
				outpatientRehabilitation = outpatientRehabilitation.replace('In Network','').trim()
				planInfo.details[fieldName] = outpatientRehabilitation
			.html "div#specialNeed3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				habilitation = $('div.details').first()?.text()?.trim()
				habilitation = habilitation.replace('In Network','').trim()
				planInfo.details[fieldName] = habilitation
			.html "div#specialNeed4Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				skillNursingFacility = $('div.details').first()?.text()?.trim()
				skillNursingFacility = skillNursingFacility.replace('In Network','').trim()
				planInfo.details[fieldName] = skillNursingFacility
			.html "div#specialNeed5Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				durableMedicalEquipment = $('div.details').first()?.text()?.trim()
				durableMedicalEquipment = durableMedicalEquipment.replace('In Network','').trim()
				planInfo.details[fieldName] = durableMedicalEquipment
			.html "div#specialNeed6Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				hospiceServices = $('div.details').first()?.text()?.trim()
				hospiceServices = hospiceServices.replace('In Network','').trim()
				planInfo.details[fieldName] = hospiceServices
			.html "div#specialNeed8Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				acupuncture = $('div.details').first()?.text()?.trim()
				acupuncture = acupuncture.replace('In Network','').trim()
				planInfo.details[fieldName] = acupuncture
			.html "div#specialNeed9Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				rehabilitativeSpeech = $('div.details').first()?.text()?.trim()
				rehabilitativeSpeech = rehabilitativeSpeech.replace('In Network','').trim()
				planInfo.details[fieldName] = rehabilitativeSpeech
			.html "div#specialNeed10Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				rehabilitativeOccupational = $('div.details').first()?.text()?.trim()
				rehabilitativeOccupational = rehabilitativeOccupational.replace('In Network','').trim()
				planInfo.details[fieldName] = rehabilitativeOccupational
			.html "div#specialNeed11Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				wellBabyVisit = $('div.details').first()?.text()?.trim()
				wellBabyVisit = wellBabyVisit.replace('In Network','').trim()
				planInfo.details[fieldName] = wellBabyVisit
			.html "div#specialNeed12Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				allergyTesting = $('div.details').first()?.text()?.trim()
				allergyTesting = allergyTesting.replace('In Network','').trim()
				planInfo.details[fieldName] = allergyTesting
			.html "div#specialNeed13Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				diabetesEducation = $('div.details').first()?.text()?.trim()
				diabetesEducation = diabetesEducation.replace('In Network','').trim()
				planInfo.details[fieldName] = diabetesEducation
			.html "div#specialNeed14Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				nutritionalCounseling = $('div.details').first()?.text()?.trim()
				nutritionalCounseling = nutritionalCounseling.replace('In Network','').trim()
				planInfo.details[fieldName] = nutritionalCounseling
			.html "div#childrensVision1Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				eyeExamForChildren = $('div.details').first()?.text()?.trim()
				eyeExamForChildren = eyeExamForChildren.replace('In Network','').trim()
				planInfo.details[fieldName] = eyeExamForChildren
			.html "div#childrensVision2Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				eyeglassesForChildren = $('div.details').first()?.text()?.trim()
				eyeglassesForChildren = eyeglassesForChildren.replace('In Network','').trim()
				planInfo.details[fieldName] = eyeglassesForChildren
			.html "div#childrensDental3Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				childFilling = $('div.details').first()?.text()?.trim()
				childFilling = childFilling.replace('In Network','').trim()
				planInfo.details[fieldName] = childFilling
			.html "div#childrensDental4Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				childDental = $('div.details').first()?.text()?.trim()
				childDental = childDental.replace('In Network','').trim()
				planInfo.details[fieldName] = childDental
			.html "div#childrensDental6Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				childRootCanal = $('div.details').first()?.text()?.trim()
				childRootCanal = childRootCanal.replace('In Network','').trim()
				planInfo.details[fieldName] = childRootCanal
			.html "div#childrensDental8Detail"
			.then (html) ->
				$ = cheerio.load html
				fieldName = $('div.ps-detail__service-label a').text().trim()
				fieldName = fieldName.replace('tooltip link','').trim()
				childMedically = $('div.details').first()?.text()?.trim()
				childMedically = childMedically.replace('In Network','').trim()
				planInfo.details[fieldName] = childMedically


			plans.push planInfo

			planTimer = Date.now() - planTimer
			console.log "#{zip} >> Plan #{linkId} took #{planTimer}ms"

			complete = plans.length / totalPlanSize
			complete = complete * 100
			complete = Number.parseFloat complete
			complete = complete.toFixed 2
			console.log "#{zip} >> Plans crawled complete - #{complete}% - #{plans.length} / #{totalPlanSize}"

			await horseman.log "#{zip} >> Back to quote page"
			.click 'div.ps-top-links a.back-to-all-plans-link-detail'
			.wait WAIT_TIME


	if plans.length > 0
		console.log "#{zip} >> Write #{plans.length} plans to target CSV file - #{outputFileName}"
		# TODO write to json files
		await writeToCsvFile outputFileName, plans, zip
	else
		console.log "#{zip} >> Nothing crawl down"

	processedZipCounty.state = 'D'
	await processedZipCounty.save()

	console.log "#{zip} >> Prepare to exit"
	clearScrapeTimeout()
	console.log "#{zip} >> Close client after clear timer"
	done()
	zipTimer = Date.now() - zipTimer
	console.log "#{zip} >> This area took #{zipTimer}ms to finish"
	cb()

writeToCsvFile = (outputFileName, plans, zip) ->
	return new Promise (resolve, reject) ->
		return resolve() unless plans.length > 0

		basicHeading =
			'Region': (p) -> p.ifpRegionCode
			'Zip': (p) -> p.zip
			'PlanType': (p) -> p.planType
			'Carrier': (p) -> p.carrier
			'PlanName': (p) -> p.planName
			'StarRating': (p) -> p.starRating
			'Premiums': (p) -> p.premiums

		detailsHeading = []
		specicalDetailsHeading = {}

		for plan in plans
			continue unless plan.details?
			lables = []
			for k, v of plan.details
				if v.individual? or v.family?
					individualHeading = "#{k} - Individual"
					familyHeading = "#{k} - Family"
					specicalDetailsHeading[individualHeading] =
						key1: k
						key2: 'individual'
					specicalDetailsHeading[familyHeading] =
						key1: k
						key2: 'family'
					lables.push individualHeading
					lables.push familyHeading
				else
					lables.push k
			detailsHeading = _.union detailsHeading, lables
			detailsHeading = _.uniq detailsHeading

		# console.log detailsHeading
		HEADING = _.union _.keys(basicHeading), detailsHeading

		detailsValueMapping = (details, label) ->
			return details[label] || '' unless specicalDetailsHeading[label]?

			keyVar = specicalDetailsHeading[label]
			return details[keyVar.key1]?[keyVar.key2] || ''

		planToCsvRowData = (plan) ->
			vals = []
			for label in HEADING
				if basicHeading[label]?
					vals.push basicHeading[label](plan)
				else
					vals.push detailsValueMapping(plan.details, label)

			return vals

		# console.log "#{zip} >> Ready to write csv file"
		out = fs.createWriteStream outputFileName, flags: 'w'
		writer = new csv.CsvWriter out
		doneWriting = false
		totalRowsShouldWrite = plans.length + 1
		writer.on 'error', (err) ->
			console.log "#{zip} >> Error occurred while writing csv"
			console.error err
			fs.unlinkSync outputFileName if fs.existsSync outputFileName
			resolve()
		writer.on 'drain', ->
			console.log "#{zip} >> Done writing csv"
			doneWriting = true
			clearTimeout writeCSVTimeOut if writeCSVTimeOut?
			resolve()
		out.on 'close', ->
			console.log "#{zip} >> Done writing csv via write stream"
			doneWriting = true
			clearTimeout writeCSVTimeOut if writeCSVTimeOut?
			resolve()

		# console.log "#{zip} >> Writing heading"
		writer.writeRecord HEADING
		# console.log "#{zip} >> Writing plan rows"
		for plan in plans
			# console.log "#{zip} >> Writing plan - #{plan.planName}"
			writer.writeRecord planToCsvRowData plan

		writeCSVTimeOut = setTimeout ->
			async.retry
				times: 5
				interval: 1000
			, (cb) ->
				return cb null, {} if doneWriting
				linecount outputFileName, (err, rowCount) ->
					console.error err if err?
					return cb new Error "Failed to count file rows" unless rowCount? and rowCount > 0
					return cb new Error "File rows count is NOT matched" unless rowCount is totalRowsShouldWrite
					return cb null, {}
			, (err) ->
				console.error err if err?
				unless doneWriting
					console.log "#{zip} >> Force done writing csv"
					doneWriting = true
					resolve()
		, 2000


module.exports.ALL_ERRORS = ALL_ERRORS

if process.argv[1] and process.argv[1].match(__filename)
	census =
		zip: '95150'
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'
		ifpRegionCode: '7'
		county: 'Santa Clara'

	scrapeCoveredCAPlanData census, (err) ->
		console.log err if err?
		console.log "#{census.zip} >> Done"
		process.exit 0
