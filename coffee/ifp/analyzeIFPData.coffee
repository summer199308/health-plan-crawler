fs = require 'fs'
_ = require 'lodash'
async = require 'async'
csv = require 'ya-csv'

queingStream = require '../util/queingStream'


async.eachSeries [1..19], (region,nextRegion) ->
	folderRootName = "resource/out/ifp/CA/#{region}"
	outputFileName = "#{folderRootName}/CoveredCA.csv"
	if fs.existsSync outputFileName
		console.log "#{region} CoveredCA.csv was already processed"
		return nextRegion()
	walker = require('walk').walk "#{folderRootName}"

	uniquePlan = []
	planInfos = []

	out = fs.createWriteStream "#{folderRootName}/CoveredCA.csv", {flags: 'w'}
	writer = new csv.CsvWriter out

	writer.writeRecord [
		'Region'
		'Zip'
		'PlanType'
		'Carrier'
		'PlanName'
		'StarRating'
		'Premiums'
		'Yearly Deductible - Individual'
		'Yearly Deductible - Family'
		'Separate Drug Deductible - Individual'
		'Separate Drug Deductible - Family'
		'Out-of-Pocket Max - Individual'
		'Out-of-Pocket Max - Family'
		'Maximum Cost per Prescription'
		'Primary Care Visit'
		'Specialist Visit'
		'Other Practitioner Office Visit'
		'Preventive Care/Screening/Immunization'
		'Laboratory Tests'
		'X-rays and Diagnostic Imaging'
		'Imaging (CT/PET Scans, MRIs)'
		'Tier 1 (Most Generic Drugs)'
		'Tier 2 (Preferred Brand Drugs)'
		'Tier 3 (Non-Preferred Brand Drugs)'
		'Tier 4 (Specialty Drugs)'
		'Outpatient Facility Fee'
		'Outpatient Surgery Physician/Surgical Services'
		'Outpatient Services Office Visits'
		'Emergency Room Facility Fee'
		'Emergency Transportation'
		'Urgent Care'
		'Emergency Room Professional Fee'
		'Inpatient Hospital Services'
		'Inpatient Physician and Surgical Services'
		'Mental/Behavioral Health Outpatient Services'
		'Mental/Behavioral Health Inpatient Facility Fee'
		'Mental/Behavioral Health Inpatient Professional Fee'
		'Substance Use Disorder Outpatient Services'
		'Substance Use Disorder Inpatient Facility Fee'
		'Substance Use Disorder Inpatient Professional Fee'
		'Prenatal Care'
		'Delivery and Maternity Care Inpatient Facility Fee'
		'Delivery and Maternity Care Inpatient Professional Fee'
		'Home Health Care Services'
		'Outpatient Rehabilitation Services'
		'Habilitation Services'
		'Skilled Nursing Facility'
		'Durable Medical Equipment'
		'Hospice Services'
		'Acupuncture'
		'Rehabilitative Speech Therapy'
		'Rehabilitative Occupational and Rehabilitative Physical Therapy'
		'Well Baby Visits and Care'
		'Allergy Testing'
		'Diabetes Education'
		'Nutritional Counseling'
		'Eye Exam for Children'
		'Eyeglasses for Children'
		'Child Filling - One Surface'
		'Child Dental Checkup'
		'Child Root Canal - Molar'
		'Child Medically Necessary Orthodontia'
	]

	walker.on "file", (root,fileStats,next) ->

		return next() unless /\.csv$/.test fileStats.name
		return next() if /^CoveredCA.csv$/.test fileStats.name
		console.log 'File Name:', fileStats.name
		stream = csv.createCsvFileReader "#{folderRootName}/#{fileStats.name}"
		count = 0
		loadTask = (task, nextRow) ->
			{data} = task

			count++
			return setImmediate nextRow if count is 1

			planInfos.push
				region : data[0]
				zip : data[1]
				planType : data[2]
				carrier : data[3]
				planName : data[4]
				starRating : data[5]
				premiums : data[6]
				yearlyDeductibleIndividual: data[7]
				yearlyDeductibleFamily: data[8]
				separateDrugDeductibleIndividual: data[9]
				separateDrugDeductibleFamily: data[10]
				outofPocketMaxIndividual: data[11]
				outofPocketMaxFamily: data[12]
				maximumCostperPrescription: data[13]
				primaryCareVisit: data[14]
				specialistVisit: data[15]
				otherPractitionerOfficeVisit: data[16]
				preventiveCareScreeningImmunization: data[17]
				laboratoryTests: data[18]
				xraysandDiagnosticImaging: data[19]
				imagingCTPETScansOrMRIs: data[20]
				tier1MostGenericDrugs: data[21]
				tier2PreferredBrandDrugs: data[22]
				tier3NonPreferredBrandDrugs: data[23]
				tier4SpecialtyDrugs: data[24]
				outpatientFacilityFee: data[25]
				outpatientSurgeryPhysicianSurgicalServices: data[26]
				outpatientServicesOfficeVisits: data[27]
				emergencyRoomFacilityFee: data[28]
				emergencyTransportation: data[29]
				urgentCare: data[30]
				emergencyRoomProfessionalFee: data[31]
				inpatientHospitalServices: data[32]
				inpatientPhysicianandSurgicalServices: data[33]
				mentalBehavioralHealthOutpatientServices: data[34]
				mentalBehavioralHealthInpatientFacilityFee: data[35]
				mentalBehavioralHealthInpatientProfessionalFee: data[36]
				substanceUseDisorderOutpatientServices: data[37]
				substanceUseDisorderInpatientFacilityFee: data[38]
				substanceUseDisorderInpatientProfessionalFee: data[39]
				prenatalCare: data[40]
				deliveryandMaternityCareInpatientFacilityFee: data[41]
				deliveryandMaternityCareInpatientProfessionalFee: data[42]
				homeHealthCareServices: data[43]
				outpatientRehabilitationServices: data[44]
				habilitationServices: data[45]
				skilledNursingFacility: data[46]
				durableMedicalEquipment: data[47]
				hospiceServices: data[48]
				acupuncture: data[49]
				rehabilitativeSpeechTherapy: data[50]
				rehabilitativeOccupationalandRehabilitativePhysicalTherapy: data[51]
				wellBabyVisitsandCare: data[52]
				allergyTesting: data[53]
				diabetesEducation: data[54]
				nutritionalCounseling: data[55]
				eyeExamforChildren: data[56]
				eyeglassesforChildren: data[57]
				childFillingOneSurface: data[58]
				childDentalCheckup: data[59]
				childRootCanalMolar: data[60]
				childMedicallyNecessaryOrthodontia: data[61]

			setImmediate nextRow

		queingStream
			stream: stream
			task: loadTask
		, ->
			# console.log planInfos

			async.eachSeries planInfos, (planInfo,nextPlan) ->

				key = "#{planInfo.planName}@#{planInfo.premiums}"
				if _.indexOf(uniquePlan, key) < 0
					uniquePlan.push key
					writer.writeRecord [
						planInfo.region
						planInfo.zip
						planInfo.planType
						planInfo.carrier
						planInfo.planName
						planInfo.starRating
						planInfo.premiums
						planInfo.yearlyDeductibleIndividual
						planInfo.yearlyDeductibleFamily
						planInfo.separateDrugDeductibleIndividual
						planInfo.separateDrugDeductibleFamily
						planInfo.outofPocketMaxIndividual
						planInfo.outofPocketMaxFamily
						planInfo.maximumCostperPrescription
						planInfo.primaryCareVisit
						planInfo.specialistVisit
						planInfo.otherPractitionerOfficeVisit
						planInfo.preventiveCareScreeningImmunization
						planInfo.laboratoryTests
						planInfo.xraysandDiagnosticImaging
						planInfo.imagingCTPETScansOrMRIs
						planInfo.tierMostGenericDrugs
						planInfo.tierPreferredBrandDrugs
						planInfo.tierNonPreferredBrandDrugs
						planInfo.tierSpecialtyDrugs
						planInfo.outpatientFacilityFee
						planInfo.outpatientSurgeryPhysicianSurgicalServices
						planInfo.outpatientServicesOfficeVisits
						planInfo.emergencyRoomFacilityFee
						planInfo.emergencyTransportation
						planInfo.urgentCare
						planInfo.emergencyRoomProfessionalFee
						planInfo.inpatientHospitalServices
						planInfo.inpatientPhysicianandSurgicalServices
						planInfo.mentalBehavioralHealthOutpatientServices
						planInfo.mentalBehavioralHealthInpatientFacilityFee
						planInfo.mentalBehavioralHealthInpatientProfessionalFee
						planInfo.substanceUseDisorderOutpatientServices
						planInfo.substanceUseDisorderInpatientFacilityFee
						planInfo.substanceUseDisorderInpatientProfessionalFee
						planInfo.prenatalCare
						planInfo.deliveryandMaternityCareInpatientFacilityFee
						planInfo.deliveryandMaternityCareInpatientProfessionalFee
						planInfo.homeHealthCareServices
						planInfo.outpatientRehabilitationServices
						planInfo.habilitationServices
						planInfo.skilledNursingFacility
						planInfo.durableMedicalEquipment
						planInfo.hospiceServices
						planInfo.acupuncture
						planInfo.rehabilitativeSpeechTherapy
						planInfo.rehabilitativeOccupationalandRehabilitativePhysicalTherapy
						planInfo.wellBabyVisitsandCare
						planInfo.allergyTesting
						planInfo.diabetesEducation
						planInfo.nutritionalCounseling
						planInfo.eyeExamforChildren
						planInfo.eyeglassesforChildren
						planInfo.childFillingOneSurface
						planInfo.childDentalCheckup
						planInfo.childRootCanalMolar
						planInfo.childMedicallyNecessaryOrthodontia
					]

				setImmediate nextPlan
			, next

	walker.on 'end', ->
		console.log "Finished"
		nextRegion()
, (err) ->
	console.log 'done'
