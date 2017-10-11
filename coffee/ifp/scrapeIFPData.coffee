###
	To run horseman, please make sure the phantomjs binary is set.
	Download the phantom/bin from here - http://phantomjs.org/download.html, based on the system;
	And then put it in the local bin folder;
###
fs = require 'fs'
async = require 'async'
csv = require 'ya-csv'
Horseman = require "node-horseman"

startedPageUrl = 'https://apply.coveredca.com/apspahbx/ahbxanonym.portal?_nfpb=true&_st=&_nfls=false&_pageLabel=previewPlanPage#'

module.exports = scrapeHealthCareGovPlanData = (census, cb) ->
	horseman = new Horseman
		timeout : 30000
		loadImages : false
		switchToNewTab : true
		webSecurity: true
		ignoreSSLErrors: true

	horseman
		.on 'error', (msg, trace) ->
			console.log msg, trace
		.on 'timeout', (timeout, msg) ->
			console.log 'timeout', msg

	{zip, annualIncome, numOfHousehold, ageOfHead, county,ifpRegionCode} = census
	totalPlanSize = 0
	pageCount = 0
	planInfo = {}
	countyNames = []

	root = "resource/out/ifp/CA/#{ifpRegionCode}"
	fs.mkdirSync root unless fs.existsSync root
	outputFileName = "#{root}/#{zip}.csv"
	if county?
		countyUri = county.name.replace /\s/g, "-"
		countyUri = countyUri.toLowerCase()
		outputFileName = "#{root}/#{zip}-#{countyUri}.csv"
	if fs.existsSync outputFileName
		census.processed = true
		console.log "ZipCode File #{zip} was already processed"
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

	horseman
		.open startedPageUrl
		.type 'input#zipcode', zip
		.type 'input#annual', annualIncome
		.select 'select#numOfHousehold', numOfHousehold
		.type 'input#agehead', ageOfHead
		.type 'input.float-left', ageOfHead
		.click 'input#continueLink'
		.wait 1000
		.log "Typing census done"
		.exists 'select#countyId'
		.then (hasMoreCounty) ->
			if hasMoreCounty
				console.log "There are more counties in the zipcodes"
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
						.log "Select county : #{county.name}"
						.select 'select#countyId', county.value
		.wait 1000
		.click 'button[title=\'Continue\']'
		.log "Click Continue button"
		.wait 1000
		.waitForNextPage()
		.click 'a[title=\'Preview Plans\']'
		.log 'Click Preview Plans button'
		.waitForNextPage()
		.switchToFrame 'myframe'
		.click 'input[title=\'SKIP TO VIEW PLANS\']'
		.log 'Click SKIP button'
		.waitForNextPage()
		.switchToFrame 'myframe'
		# .waitForSelector 'a.view-detail'
		.waitFor (selector) ->
			return $(selector).length > 1
		, 'a.view-detail', true
		# .screenshot('out/ifp-quote.png')
		.html 'span#filteredPlanCount'
		.then (html) ->
			totalPlanSize = parseInt html
			console.log "Total plans number : #{totalPlanSize}"
		.evaluate (selector) ->
			detailsLinkIds = []
			$(selector).each ->
				detailsLinkIds.push $(@).attr('id')
			return detailsLinkIds
		, 'a.view-detail'
		.then (detailsLinkIds) ->
			pageCount = parseInt(totalPlanSize / 12) + 1
			console.log "Total page count : #{pageCount}"
			async.eachSeries [1..pageCount], (pageNum, nextPage) ->
				num = pageNum - 1
				# return next() unless num is 1
				horseman
					.click "div#pagination li:eq(#{num}) a"
					.catch (err) ->
						console.log 'Click pagination failed'
					.log "Process plan units on page #{pageNum}"
					# .screenshot("out/ifp-quote-#{pageNum}.png")
					.evaluate (selector) ->
						detailsLinkIds = []
						$(selector).each ->
							detailsLinkIds.push $(@).attr('id')
						return detailsLinkIds
					, 'a.view-detail'
					.then (detailsLinkIds) ->
						# console.log detailsLinkIds
						firstClickPerPage = true
						async.eachSeries detailsLinkIds, (linkId, next) ->
							num = pageNum - 1
							num = pageNum if pageNum isnt 1 and firstClickPerPage
							horseman
								.click "div#pagination li:eq(#{num}) a"
								.catch (err) ->
									console.log 'Click pagination failed'
								.log "a##{linkId}"
								# .screenshot("out/ifp-quote-#{linkId}.png")
								.click "a##{linkId}"
								.text "a##{linkId}"
								.then (text) ->
									planType = text?.trim().split(" ", 1)
									# console.log "PlanType:", planType.toString()
									planInfo.ifpRegionCode = ifpRegionCode
									planInfo.zip = zip
									planInfo.planType = planType

								.attribute "img##{linkId}", "alt"
								.then (attribute) ->
									# console.log "Carrier:", attribute
									planInfo.carrier = attribute

									horseman
									.text "a##{linkId}"
									.then (text) ->
										planName = attribute + " " + text?.trim()
										# console.log "PlanName:", planName
										planInfo.planName = planName

								.count "div.details a i.icon-star"
								.then (count) ->
									starRating = if count is 0 then "NA" else count.toString()
									# console.log "StarRating:", starRating
									planInfo.starRating = starRating

								.text "table.table tbody tr:eq(0) td p"
								.then (text) ->
									premiums = text?.trim()
									premiums = parseDouble(premiums)/2
									# console.log "Premiums:", premiums
									planInfo.premiums = premiums

								.text "div#simplifiedDeductibleDetail div.details p:eq(0)"
								.then (text) ->
									individualAnnualDeductibleAmount = text?.trim().split(" ", 1).toString()
									# console.log "IndividualAnnualDeductibleAmount:", individualAnnualDeductibleAmount
									planInfo.individualAnnualDeductibleAmount = individualAnnualDeductibleAmount

								.text "div#simplifiedDeductibleDetail div.details p:eq(1)"
								.then (text) ->
									familyAnnualDeductibleAmount = text?.trim().split(" ", 1).toString()
									# console.log "FamilyAnnualDeductibleAmount:", familyAnnualDeductibleAmount
									planInfo.familyAnnualDeductibleAmount = familyAnnualDeductibleAmount

								.text "div#simplifiedOOPMaxDetail div.details p:eq(0)"
								.then (text) ->
									individualAnnualOOPLimitAmount = text?.trim().split(" ", 1).toString()
									# console.log "IndividualAnnualOOPLimitAmount:", individualAnnualOOPLimitAmount
									planInfo.individualAnnualOOPLimitAmount = individualAnnualOOPLimitAmount

								.text "div#simplifiedOOPMaxDetail div.details p:eq(1)"
								.then (text) ->
									familyAnnualOOPLimitAmount = text?.trim().split(" ", 1).toString()
									# console.log "FamilyAnnualOOPLimitAmount:", familyAnnualOOPLimitAmount
									planInfo.familyAnnualOOPLimitAmount = familyAnnualOOPLimitAmount

								.text "div#doctorVisit1Detail div.details:eq(0) p small"
								.then (text) ->
									if text?.trim().indexOf("First 3 visits") isnt -1
										primaryCareVisit = text.substring(18,27)
									else
										primaryCareVisit = text?.trim().split(" ", 2).toString()
										primaryCareVisit = primaryCareVisit.replace(","," ")
									# console.log "PrimaryCareVisit:", primaryCareVisit
									planInfo.primaryCareVisit = primaryCareVisit

								.text "div#doctorVisit2Detail div.details:eq(0) p small"
								.then (text) ->
									specialistVisit = text?.trim().split(" ", 2).toString()
									specialistVisit = specialistVisit.replace(","," ")
									# console.log "SpecialistVisit:", specialistVisit
									planInfo.specialistVisit = specialistVisit

								.text "div#urgent1Detail div.details:eq(0) p small"
								.then (text) ->
									emergencyRoomServices = text?.trim().split(" ", 2).toString()
									emergencyRoomServices = emergencyRoomServices.replace(","," ")
									# console.log "EmergencyRoomServices:", emergencyRoomServices
									planInfo.emergencyRoomServices = emergencyRoomServices

								.text "div#drug1Detail div.details:eq(0) p small"
								.then (text) ->
									genericDrugs = text?.trim().split(" ", 2).toString()
									genericDrugs = genericDrugs.replace(","," ")
									# console.log "GenericDrugs:", genericDrugs
									planInfo.genericDrugs = genericDrugs

								.text "div#test1Detail div.details:eq(0) p small"
								.then (text) ->
									laboratoryOutPatientProfessionalServices = text?.trim().split(" ", 2).toString()
									laboratoryOutPatientProfessionalServices = laboratoryOutPatientProfessionalServices.replace(","," ")
									# console.log "LaboratoryOutPatientProfessionalServices:", laboratoryOutPatientProfessionalServices
									planInfo.laboratoryOutPatientProfessionalServices = laboratoryOutPatientProfessionalServices

								.text "div#hospital1Detail div.details:eq(0) p small"
								.then (text) ->
									inpatientHospitalServices = text?.trim().split(" ", 2).toString()
									inpatientHospitalServices = inpatientHospitalServices.replace(","," ")
									# console.log "InpatientHospitalServices:", inpatientHospitalServices
									planInfo.inpatientHospitalServices = inpatientHospitalServices

								.text "div#test2Detail div.details:eq(0) p small"
								.then (text) ->
									xRayDiagnosticImaging = text?.trim().split(" ", 2).toString()
									xRayDiagnosticImaging = xRayDiagnosticImaging.replace(","," ")
									# console.log "XRayDiagnosticImaging:", xRayDiagnosticImaging
									planInfo.xRayDiagnosticImaging = xRayDiagnosticImaging

								.text "div#drug2Detail div.details:eq(0) p small"
								.then (text) ->
									preferredBrandDrugs = text?.trim().split(" ", 2).toString()
									preferredBrandDrugs = preferredBrandDrugs.replace(","," ")
									# console.log "PreferredBrandDrugs:", preferredBrandDrugs
									planInfo.preferredBrandDrugs = preferredBrandDrugs

								.text "div#drug3Detail div.details:eq(0) p small"
								.then (text) ->
									nonPreferredBrandDrugs = text?.trim().split(" ", 2).toString()
									nonPreferredBrandDrugs = nonPreferredBrandDrugs.replace(","," ")
									# console.log "NonPreferredBrandDrugs:", nonPreferredBrandDrugs
									planInfo.nonPreferredBrandDrugs = nonPreferredBrandDrugs

								.text "div#drug4Detail div.details:eq(0) p small"
								.then (text) ->
									specialtyDrugs = text?.trim().split(" ", 2).toString()
									specialtyDrugs = specialtyDrugs.replace(","," ")
									# console.log "SpecialtyDrugs:", specialtyDrugs
									planInfo.specialtyDrugs = specialtyDrugs

									writer.writeRecord [
										planInfo.ifpRegionCode
										planInfo.zip
										planInfo.planType
										planInfo.carrier
										planInfo.planName
										planInfo.starRating
										planInfo.premiums
										planInfo.individualAnnualDeductibleAmount
										planInfo.familyAnnualDeductibleAmount
										planInfo.individualAnnualOOPLimitAmount
										planInfo.familyAnnualOOPLimitAmount
										planInfo.primaryCareVisit
										planInfo.specialistVisit
										planInfo.emergencyRoomServices
										planInfo.genericDrugs
										planInfo.laboratoryOutPatientProfessionalServices
										planInfo.inpatientHospitalServices
										planInfo.xRayDiagnosticImaging
										planInfo.preferredBrandDrugs
										planInfo.nonPreferredBrandDrugs
										planInfo.specialtyDrugs
									]

								# .html 'div#estimatedCostDetail' #TODO add file path to save html file
								# .then (html) ->
								# 	console.log html
								.log 'Back to plans'
								.click 'div#detail a.detailBackToAll'
								.wait 100
								.then ->
									firstClickPerPage = false
									next()
						, nextPage
			, ->
				horseman.close()
				cb null, countyNames

if process.argv[1] and process.argv[1].match(__filename)
	census =
		zip: '96142'
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'

	scrapeHealthCareGovPlanData census, (err) ->
		console.log err if err?
		console.log 'Done'
		process.exit 0
