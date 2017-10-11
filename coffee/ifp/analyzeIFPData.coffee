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

    out = fs.createWriteStream "#{folderRootName}/CoveredCA.csv", {flags: 'w'}
    writer = new csv.CsvWriter out


    uniquePlan = []


    walker.on "file", (root,fileStats,next) ->
        planInfos = []
        return next() unless /\.csv$/.test fileStats.name
        return next() if /^CoveredCA.csv$/.test fileStats.name
        console.log 'File Name:', fileStats.name
        stream = csv.createCsvFileReader "#{folderRootName}/#{fileStats.name}"
        loadTask = (task, nextRow) ->
            {data} = task

            return setImmediate nextRow unless _.toNumber(data[1])?

            planInfos.push
                region : region
                zip : data[0]
                planType : data[1]
                carrier : data[2]
                planName : data[3]
                starRating : data[4]
                premiums : data[5]
                individualAnnualDeductibleAmount : data[6]
                familyAnnualDeductibleAmount : data[7]
                individualAnnualOOPLimitAmount : data[8]
                familyAnnualOOPLimitAmount : data[9]
                primaryCareVisit : data[10]
                specialistVisit : data[11]
                emergencyRoomServices : data[12]
                genericDrugs : data[13]
                laboratoryOutPatientProfessionalServices : data[14]
                inpatientHospitalServices : data[15]
                xRayDiagnosticImaging : data[16]
                preferredBrandDrugs : data[17]
                nonPreferredBrandDrugs : data[18]
                specialtyDrugs : data[19]

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

                setImmediate nextPlan
            , next


    walker.on 'end', ->
        console.log "Finished"
        nextRegion()
, (err) ->
    console.log 'done'
