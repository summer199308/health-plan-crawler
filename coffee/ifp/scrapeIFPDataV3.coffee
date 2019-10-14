###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
async = require 'async'
csv = require 'ya-csv'
Horseman = require "node-horseman"

WAIT_TIME = process.env.OPT_WAIT_TIME || 1000
WAIT_TIME = parseInt WAIT_TIME

startedPageUrl = 'https://apply.coveredca.com/lw-shopandcompare'

module.exports = scrapeHealthCareGovPlanData = (census, cb) ->
	{zip, annualIncome, numOfHousehold, ageOfHead, county, ifpRegionCode} = census
	totalPlanSize = 0
	pageCount = 0
	planInfo = {}

	# start point
	console.log "#{zip} >> Zipcode:", zip
	console.log "#{zip} >> Region Code:", ifpRegionCode
	console.log "#{zip} >> County Name:", county

	zipTimer = Date.now()
	stepTimer = Date.now()
	root = "resource/out/ifp/CA/#{ifpRegionCode}"
	fs.mkdirSync root unless fs.existsSync root
	outputFileName = "#{root}/#{zip}.csv"
	countyUri = county.replace /\s/g, "-"
	countyUri = countyUri.toLowerCase()
	outputFileName = "#{root}/#{zip}-#{countyUri}.csv"
	if fs.existsSync outputFileName
		census.processed = true
		console.log "#{zip} >> ZipCode File #{zip} was already processed"
		return cb()

	out = fs.createWriteStream outputFileName, flags: 'w'
	writer = new csv.CsvWriter out
	writer.writeRecord [
		'Region'
		'Zip'
		'PlanType'
		'Carrier'
		'PlanName'
		'StarRating'
		'Premiums'
		'IndividualAnnualDeductibleAmount'
		'FamilyAnnualDeductibleAmount'
		'IndividualAnnualOOPLimitAmount'
		'FamilyAnnualOOPLimitAmount'
		'PrimaryCareVisit'
		'SpecialistVisit'
		'EmergencyRoomServices'
		'GenericDrugs'
		'LaboratoryOutPatientProfessionalServices'
		'InpatientHospitalServices'
		'XRayDiagnosticImaging'
		'PreferredBrandDrugs'
		'NonPreferredBrandDrugs'
		'SpecialtyDrugs'
	]

	completed = false
	horseman = new Horseman
		timeout : 2*60*WAIT_TIME
		loadImages : false
		switchToNewTab : true
		webSecurity: true
		ignoreSSLErrors: true

	done = ->
		completed = true # indicate completed so the regular scraping doesn't callback
		horseman.close()

	clearOutput = ->
		fs.unlinkSync outputFileName if fs.existsSync outputFileName

	scrapeTimeOut = setTimeout ->
		return if completed
		console.log "#{zip} >> 5 mins Timeout !!! Process next location ..."
		done()
		clearOutput()
		cb()
	, 5*60*WAIT_TIME # 5 mins time out to process next location

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
	# 		clearOutput()
	# 		cb()
	# 	.on 'timeout', (timeout) ->
	# 		console.log "#{zip} >> Timeout occurred for #{zip}"
	# 		console.log "#{zip} >> Process next location ..."
	# 		done()
	# 		clearOutput()
	# 		cb()

	stepTimer = Date.now() - stepTimer
	console.log "#{zip} >> Initialization took #{stepTimer}ms"
	stepTimer = Date.now()
	horseman
		.viewport 1024, 1366 # iPad pro
		.open startedPageUrl
		.wait WAIT_TIME
		.catch (err) ->
			console.error err
			console.log "#{zip} >> Failed to open the started page"
			clearScrapeTimeout()
			done()
			cb()
		.waitFor (selector) ->
			return $(selector).length > 0
		, 'input#screeningquestions-enrollyear', true
		.text 'span#react-select-screeningquestions-enrollyear--value-item'
		.then (year) ->
			console.log "#{zip} >> Working on plan year #{year}"
			stepTimer = Date.now() - stepTimer
			console.log "#{zip} >> Open first page took #{stepTimer}ms"
			stepTimer = Date.now()
		.type 'input#screeningquestions-zip', zip
		# type another entry to trigger the focus lost event of zip
		.type 'input#screeningquestions-householdincomeperyear', annualIncome
		.wait WAIT_TIME
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
				done()
				clearOutput()
				clearScrapeTimeout()
				return cb()
			else
				horseman
					.type 'input#screeningquestions-howmanypeopleinhousehold', numOfHousehold
					.keyboardEvent 'keypress', 16777221 # press enter
					# .screenshot("ifp-census-#{zip}.png")
					.wait 2*WAIT_TIME
					.type 'input#screeningquestions-age-0', ageOfHead
					.type 'input#screeningquestions-age-1', ageOfHead
					.exists 'input#screeningquestions-county'
					.then (hasMoreCounty) ->
						if hasMoreCounty
							console.log "#{zip} >> There are more counties in the zipcodes"
							horseman
								.log "#{zip} >> Select county : #{county}"
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
						console.error err
						console.log "#{zip} >> Failed to Click Continue button"
					# .screenshot('ifp-census-2.png')
					.click 'button#shopandcompare-previewplans'
					.log "#{zip} >> Click Preview Plans button"
					.waitForNextPage()
					.catch (err) ->
						console.error err
						console.log "#{zip} >> Failed to Click Preview Plans button"
						clearScrapeTimeout()
						done()
						cb()
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
						console.error err
						console.log "#{zip} >> Failed to open the quote page"
					# .screenshot('ifp-census-5.png')
					.switchToFrame 'myframe'
					.waitFor (selector) ->
						return $(selector).length > 0
					, "div.cp-tile a.detail.gtm_detail", true
					# .screenshot('ifp-quote-1.png')
					.text 'span#filteredPlanCount'
					.then (html) ->
						totalPlanSize = parseInt html
						console.log "#{zip} >> Total plans number : #{totalPlanSize}"
						stepTimer = Date.now() - stepTimer
						console.log "#{zip} >> Landing on quote page took #{stepTimer}ms"
						stepTimer = Date.now()
					.evaluate (selector) ->
						detailsLinkIds = []
						$(selector).each ->
							detailsLinkIds.push $(@).attr('id')
						return detailsLinkIds
					, 'div.cp-tile a.detail.gtm_detail'
					.then (detailsLinkIds) ->
						pageCount = parseInt(totalPlanSize / 12) + 1
						console.log "#{zip} >> Total page count : #{pageCount}"
						async.eachSeries [1..pageCount], (pageNum, nextPage) ->
							horseman
								.text "div#pagination div.cp-pagination span.cp-pagination__content"
								.then (currentPage) ->
									currentPage = currentPage.trim()
									currentPage = currentPage.slice 0, 1
									currentPage = parseInt currentPage
									if pageNum isnt currentPage
										horseman
											.click "div#pagination span.cp-pagination__btn--right a.next"
											.catch (err) ->
												console.log "#{zip} >> Click pagination failed"
								.log "#{zip} >> Process plan units on page #{pageNum}"
								.screenshot("out/ifp-quote-#{pageNum}.png")
								.evaluate (selector) ->
									detailsLinkIds = []
									$(selector).each ->
										detailsLinkIds.push $(@).attr('id')
									return detailsLinkIds
								, 'div.cp-tile a.detail.gtm_detail'
								.then (detailsLinkIds) ->
									# console.log detailsLinkIds
									planTimer = Date.now()
									async.eachSeries detailsLinkIds, (linkId, next) ->
										planTimer = Date.now()
										horseman
											.log "#{zip} >> View plan ##{linkId}"
											.screenshot("out/ifp-quote-#{linkId}.png")
											.click "a##{linkId}"
											.attribute "a##{linkId} img.cp-tile__img", "alt"
											.then (attribute) ->
												console.log "#{zip} >> Carrier:", attribute
												planInfo.carrier = attribute
												planInfo.ifpRegionCode = ifpRegionCode
												planInfo.zip = zip

												horseman
													.evaluate (selector) ->
														return $(selector).attr('data-original-title')
													, "div#detailHead div.tile-header p a##{linkId}"
													.then (title) ->
														title ?= ''
														title = title.replace(/\s\s+/g, ' ').trim()
														planName = "#{attribute} #{title}"
														console.log "#{zip} >> PlanName:", planName
														planInfo.planName = planName

											# .count "div.details a i.icon-star"
											# .then (count) ->
											# 	starRating = if count is 0 then "NA" else count.toString()
											# 	# console.log "#{zip} >> StarRating:", starRating
											# 	planInfo.starRating = starRating
											#
											# .text "table.table tbody tr:eq(0) td p"
											# .then (text) ->
											# 	premiums = text?.trim().replace("$","").toString()
											# 	premiums = parseFloat(premiums)/2
											# 	# console.log "#{zip} >> Premiums:", premiums
											# 	premiums = "$#{premiums}"
											# 	planInfo.premiums = premiums
											#
											# .text "div#simplifiedDeductibleDetail div.details p:eq(0)"
											# .then (text) ->
											# 	individualAnnualDeductibleAmount = text?.trim().split(" ", 1).toString()
											# 	# console.log "#{zip} >> IndividualAnnualDeductibleAmount:", individualAnnualDeductibleAmount
											# 	planInfo.individualAnnualDeductibleAmount = individualAnnualDeductibleAmount
											#
											# .text "div#simplifiedDeductibleDetail div.details p:eq(1)"
											# .then (text) ->
											# 	familyAnnualDeductibleAmount = text?.trim().split(" ", 1).toString()
											# 	# console.log "#{zip} >> FamilyAnnualDeductibleAmount:", familyAnnualDeductibleAmount
											# 	planInfo.familyAnnualDeductibleAmount = familyAnnualDeductibleAmount
											#
											# .text "div#simplifiedOOPMaxDetail div.details p:eq(0)"
											# .then (text) ->
											# 	individualAnnualOOPLimitAmount = text?.trim().split(" ", 1).toString()
											# 	# console.log "#{zip} >> IndividualAnnualOOPLimitAmount:", individualAnnualOOPLimitAmount
											# 	planInfo.individualAnnualOOPLimitAmount = individualAnnualOOPLimitAmount
											#
											# .text "div#simplifiedOOPMaxDetail div.details p:eq(1)"
											# .then (text) ->
											# 	familyAnnualOOPLimitAmount = text?.trim().split(" ", 1).toString()
											# 	# console.log "#{zip} >> FamilyAnnualOOPLimitAmount:", familyAnnualOOPLimitAmount
											# 	planInfo.familyAnnualOOPLimitAmount = familyAnnualOOPLimitAmount
											#
											# .text "div#doctorVisit1Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	if text?.trim().indexOf("First 3 visits") isnt -1
											# 		primaryCareVisit = text.substring(18,27)
											# 	else
											# 		primaryCareVisit = text?.trim().split(" ", 2).toString()
											# 		primaryCareVisit = primaryCareVisit.replace(","," ")
											# 	# console.log "#{zip} >> PrimaryCareVisit:", primaryCareVisit
											# 	planInfo.primaryCareVisit = primaryCareVisit
											#
											# .text "div#doctorVisit2Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	specialistVisit = text?.trim().split(" ", 2).toString()
											# 	specialistVisit = specialistVisit.replace(","," ")
											# 	# console.log "#{zip} >> SpecialistVisit:", specialistVisit
											# 	planInfo.specialistVisit = specialistVisit
											#
											# .text "div#urgent1Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	emergencyRoomServices = text?.trim().split(" ", 2).toString()
											# 	emergencyRoomServices = emergencyRoomServices.replace(","," ")
											# 	# console.log "#{zip} >> EmergencyRoomServices:", emergencyRoomServices
											# 	planInfo.emergencyRoomServices = emergencyRoomServices
											#
											# .text "div#drug1Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	genericDrugs = text?.trim().split(" ", 2).toString()
											# 	genericDrugs = genericDrugs.replace(","," ")
											# 	# console.log "#{zip} >> GenericDrugs:", genericDrugs
											# 	planInfo.genericDrugs = genericDrugs
											#
											# .text "div#test1Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	laboratoryOutPatientProfessionalServices = text?.trim().split(" ", 2).toString()
											# 	laboratoryOutPatientProfessionalServices = laboratoryOutPatientProfessionalServices.replace(","," ")
											# 	# console.log "#{zip} >> LaboratoryOutPatientProfessionalServices:", laboratoryOutPatientProfessionalServices
											# 	planInfo.laboratoryOutPatientProfessionalServices = laboratoryOutPatientProfessionalServices
											#
											# .text "div#hospital1Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	inpatientHospitalServices = text?.trim().split(" ", 2).toString()
											# 	inpatientHospitalServices = inpatientHospitalServices.replace(","," ")
											# 	# console.log "#{zip} >> InpatientHospitalServices:", inpatientHospitalServices
											# 	planInfo.inpatientHospitalServices = inpatientHospitalServices
											#
											# .text "div#test2Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	xRayDiagnosticImaging = text?.trim().split(" ", 2).toString()
											# 	xRayDiagnosticImaging = xRayDiagnosticImaging.replace(","," ")
											# 	# console.log "#{zip} >> XRayDiagnosticImaging:", xRayDiagnosticImaging
											# 	planInfo.xRayDiagnosticImaging = xRayDiagnosticImaging
											#
											# .text "div#drug2Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	preferredBrandDrugs = text?.trim().split(" ", 2).toString()
											# 	preferredBrandDrugs = preferredBrandDrugs.replace(","," ")
											# 	# console.log "#{zip} >> PreferredBrandDrugs:", preferredBrandDrugs
											# 	planInfo.preferredBrandDrugs = preferredBrandDrugs
											#
											# .text "div#drug3Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	nonPreferredBrandDrugs = text?.trim().split(" ", 2).toString()
											# 	nonPreferredBrandDrugs = nonPreferredBrandDrugs.replace(","," ")
											# 	# console.log "#{zip} >> NonPreferredBrandDrugs:", nonPreferredBrandDrugs
											# 	planInfo.nonPreferredBrandDrugs = nonPreferredBrandDrugs
											#
											# .text "div#drug4Detail div.details:eq(0) p small"
											# .then (text) ->
											# 	specialtyDrugs = text?.trim().split(" ", 2).toString()
											# 	specialtyDrugs = specialtyDrugs.replace(","," ")
											# 	# console.log "#{zip} >> SpecialtyDrugs:", specialtyDrugs
											# 	planInfo.specialtyDrugs = specialtyDrugs
											#
											# 	writer.writeRecord [
											# 		planInfo.ifpRegionCode
											# 		planInfo.zip
											# 		planInfo.planType
											# 		planInfo.carrier
											# 		planInfo.planName
											# 		planInfo.starRating
											# 		planInfo.premiums
											# 		planInfo.individualAnnualDeductibleAmount
											# 		planInfo.familyAnnualDeductibleAmount
											# 		planInfo.individualAnnualOOPLimitAmount
											# 		planInfo.familyAnnualOOPLimitAmount
											# 		planInfo.primaryCareVisit
											# 		planInfo.specialistVisit
											# 		planInfo.emergencyRoomServices
											# 		planInfo.genericDrugs
											# 		planInfo.laboratoryOutPatientProfessionalServices
											# 		planInfo.inpatientHospitalServices
											# 		planInfo.xRayDiagnosticImaging
											# 		planInfo.preferredBrandDrugs
											# 		planInfo.nonPreferredBrandDrugs
											# 		planInfo.specialtyDrugs
											# 	]
											#
											# # .html 'div#estimatedCostDetail' #TODO add file path to save html file
											# # .then (html) ->
											# # 	console.log html
											.log "#{zip} >> Back to quote page"
											.click 'div.ps-top-links a.back-to-all-plans-link-detail'
											.wait WAIT_TIME
											.then ->
												planTimer = Date.now() - planTimer
												console.log "#{zip} >> Plan #{linkId} took #{planTimer}ms"
												next()
									, nextPage
						, ->
							clearScrapeTimeout()
							done()
							zipTimer = Date.now() - zipTimer
							console.log "#{zip} >> All plans took #{zipTimer}ms"
							cb()

if process.argv[1] and process.argv[1].match(__filename)
	census =
		zip: '91759'
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'
		ifpRegionCode: '17'
		county: 'San Bernardino'

	scrapeHealthCareGovPlanData census, (err) ->
		console.log err if err?
		console.log "#{census.zip} >> Done"
		process.exit 0
