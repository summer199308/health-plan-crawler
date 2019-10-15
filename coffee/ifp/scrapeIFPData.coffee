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
	{zip, annualIncome, numOfHousehold, ageOfHead, county, ifpRegionCode} = census
	totalPlanSize = 0
	pageCount = 0
	planInfo = {}
	countyNames = []

	zipTimer = Date.now()
	stepTimer = Date.now()
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

	# start point
	console.log "Zipcode:", zip
	console.log "Region Code:", ifpRegionCode
	console.log "County Name:", county.name if county?.name?

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

	horseman = new Horseman
		timeout : 30000
		loadImages : false
		switchToNewTab : true
		webSecurity: true
		ignoreSSLErrors: true
		# diskCache: true


	horseman
		.on 'error', (msg, trace) ->
			console.log "Error occurred for #{zip}"
			console.log msg
			console.log trace
			return if msg? and msg is "TypeError: null is not an object (evaluating 'data.total_hits')"
			console.log "Process next location ..."
			fs.unlinkSync outputFileName if fs.existsSync outputFileName
			horseman.close()
			cb null, countyNames
		.on 'timeout', (timeout) ->
			console.log "Timeout occurred for #{zip}"
			console.log "Process next location ..."
			fs.unlinkSync outputFileName if fs.existsSync outputFileName
			horseman.close()
			cb null, countyNames

	stepTimer = Date.now() - stepTimer
	console.log "Initialization took #{stepTimer}ms"
	stepTimer = Date.now()
	horseman
		.open startedPageUrl
		.waitFor (selector) ->
			return $(selector).length > 0
		, 'select#previewplancoverageyear', true
		.value 'select#previewplancoverageyear'
		.then (year) ->
			console.log "Working on plan year #{year}"
			stepTimer = Date.now() - stepTimer
			console.log "Open first page took #{stepTimer}ms"
			stepTimer = Date.now()
		.type 'input#zipcode', zip
		# type another entry to trigger the focus lost event of zip
		.type 'input#annual', annualIncome
		.wait 500
		# .screenshot("ifp-census-#{zip}.png")
		.evaluate (selector) ->
			return $(selector).parent().is(":visible")
		, "div.ui-dialog div#zipCode-popup"
		.then (hasZipInvalidPopup) ->
			if hasZipInvalidPopup
				console.log "Zip Code #{zip} is not in Service Area"
				console.log "Process next location ..."
				fs.unlinkSync outputFileName if fs.existsSync outputFileName
				horseman.close()
				return cb null, countyNames
			else
				horseman
					.select 'select#numOfHousehold', numOfHousehold
					.wait 500
					.type 'input#agehead', ageOfHead
					.type 'input.float-left', ageOfHead
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
					.log "Typing census done"
					.click 'input#continueLink'
					.wait 1000
					# .screenshot('ifp-census-1.png')
					.exists 'button[title=\'Continue\']'
					.then (hasContinueBtn) ->
						unless hasContinueBtn
							console.log "Process next location as there is NOT the Continue button"
							fs.unlinkSync outputFileName if fs.existsSync outputFileName
							horseman.close()
							cb null, countyNames
					.click 'button[title=\'Continue\']'
					.log "Click Continue button"
					.wait 1000
					.waitForNextPage()
					# .screenshot('ifp-census-2.png')
					.exists 'a[title=\'Preview Plans\']'
					.then (hasPreviewBtn) ->
						unless hasPreviewBtn
							console.log "Process next location as there is NOT the Preview Plans button"
							fs.unlinkSync outputFileName if fs.existsSync outputFileName
							horseman.close()
							cb null, countyNames
					.click 'a[title=\'Preview Plans\']'
					.log 'Click Preview Plans button'
					.waitForNextPage()
					# .screenshot('ifp-census-3.png')
					.switchToFrame 'myframe'
					.click 'input[title=\'SKIP\']'
					.log 'Click SKIP button to skip prescription drug question'
					.wait 1000
					# .screenshot('ifp-census-4.png')
					.switchToFrame 'myframe'
					.click 'input[title=\'SKIP\']'
					.log 'Click SKIP button to skip doctor search'
					.waitForNextPage()
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
						console.log "Total plans number : #{totalPlanSize}"
						stepTimer = Date.now() - stepTimer
						console.log "Landing on quote page took #{stepTimer}ms"
						stepTimer = Date.now()
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
							horseman
								.exists "div#pagination li a:contains('#{pageNum}')"
								.then (hasPaginationLink) ->
									if hasPaginationLink
										horseman
											.click "div#pagination li a:contains('#{pageNum}')"
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
									planTimer = Date.now()
									async.eachSeries detailsLinkIds, (linkId, next) ->
										planTimer = Date.now()
										horseman
											.exists "div#pagination li a:contains('#{pageNum}')"
											.then (hasPaginationLink) ->
												if hasPaginationLink
													horseman
														.click "div#pagination li a:contains('#{pageNum}')"
														.catch (err) ->
															console.log 'Click pagination failed'
											.log "View plan ##{linkId}"
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
													.evaluate (selector) ->
														return $(selector).attr('data-original-title')
													, "div#detailHead div.tile-header p a##{linkId}"
													.then (title) ->
														title ?= ''
														title = title.replace(/\s\s+/g, ' ').trim()
														planName = "#{attribute} #{title}"
														console.log "PlanName:", planName
														planInfo.planName = planName

											.count "div.details a i.icon-star"
											.then (count) ->
												starRating = if count is 0 then "NA" else count.toString()
												# console.log "StarRating:", starRating
												planInfo.starRating = starRating

											.text "table.table tbody tr:eq(0) td p"
											.then (text) ->
												premiums = text?.trim().replace("$","").toString()
												premiums = parseFloat(premiums)/2
												# console.log "Premiums:", premiums
												premiums = "$#{premiums}"
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
											.log 'Back to quote page'
											.click 'div#detail a.detailBackToAll'
											.wait 100
											.then ->
												planTimer = Date.now() - planTimer
												console.log "Plan #{linkId} took #{planTimer}ms"
												next()
									, nextPage
						, ->
							horseman.close()
							zipTimer = Date.now() - zipTimer
							console.log "Zipcode #{zip} took #{zipTimer}ms"
							cb null, countyNames

if process.argv[1] and process.argv[1].match(__filename)
	census =
		zip: '90404'
		annualIncome: '80000'
		numOfHousehold: '2'
		ageOfHead: '35'
		ifpRegionCode: '16'

	scrapeHealthCareGovPlanData census, (err) ->
		console.log err if err?
		console.log 'Done'
		process.exit 0
