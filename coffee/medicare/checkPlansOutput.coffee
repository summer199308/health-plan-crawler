fs = require 'fs'
_ = require 'lodash'
csv = require 'ya-csv'
cheerio = require 'cheerio'

queingStream = require '../util/queingStream'


allPlans = []

# stream = csv.createCsvFileReader 'resource/in/allplans.csv'
stream = csv.createCsvFileReader 'resource/in/checkplans.csv'
loadTask = (task, nextRow) ->
	{data} = task

	allPlans.push
		planId: data[0]
		state: data[1]

	setImmediate nextRow

plan2FilePath = (p) ->
	return "resource/out/html/#{p.state}/#{p.planId}.html"

queingStream
	stream: stream
	task: loadTask
, ->
	console.log "Total plans - #{allPlans.length}"

	# allPlans = [
	# 	planId: 'H1099-006-0'
	# 	state: 'FL'
	# ]

	questionableOutputList = []
	noneAvailableOutputList = []
	count = allPlans.length
	for plan in allPlans
		count--
		filePath = plan2FilePath plan
		continue unless fs.existsSync filePath

		console.log "Checking #{plan.planId} - #{plan.state} - #{count}"
		html = fs.readFileSync filePath
		$ = cheerio.load html
		planName = $('div.BasicPlanInfo span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel_BenefitsOverview_PlanNameLabel').text()
		console.log planName
		unless planName?.length > 0
			console.log "Plan name not found"
			questionableOutputList.push plan
			continue
		planOrg = $('div.BasicPlanInfo div.BasicPlanOrg span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanOverviewPanel_OverAllOverview_PlanOrgLabel').text()
		console.log planOrg
		unless planOrg?.length > 0
			console.log "Plan org not found"
			questionableOutputList.push plan
			continue
		planType = $('div.BasicPlanInfo div.BasicPlanType span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanOverviewPanel_OverAllOverview_PlanTypeHelp_ContextualHelpLabel').text()
		console.log planType
		unless planType?.length > 0
			console.log "Plan type not found"
			questionableOutputList.push plan
			continue
		planAddr = $('div.BasicPlanInfo span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanOverviewPanel_OverAllOverview_PlanAddr1Label').text()
		console.log planAddr
		unless planAddr?.length > 0
			console.log "Plan addr not found"
			questionableOutputList.push plan
			continue
		healthPlanPremium = $('div.DrugsEstimatedCostsPanel span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_DrugCostPanel_DCCMonthlyPlanPremiumText').text()
		console.log healthPlanPremium
		unless healthPlanPremium?.length > 0
			console.log "Monthly Health Plan Premium not found"
			questionableOutputList.push plan
			continue
		drugPlanPremium = $('div.DrugsEstimatedCostsPanel span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_DrugCostPanel_DCCMonthlyDrugPremiumText').text()
		console.log drugPlanPremium
		unless drugPlanPremium?.length > 0
			console.log "Monthly Drug Plan Premium not found"
			questionableOutputList.push plan
			continue
		planDeductible = $('div#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel_BenefitsTabCostsPanel span#ctl00_ctl00_ctl00_MCGMainContentPlaceHolder_ToolContentPlaceHolder_PlanFinderContentPlaceHolder_PlanDetailTabContainer_PlanBenefitsPanel_BenefitsInfoRep_ctl01_BenefitsServicesRep_ctl00_BenefitsCostsRep_ctl00_CostsText').text()
		console.log planDeductible
		unless planDeductible?.length > 0
			console.log "Plan Deductible not found"
			noneAvailableOutputList.push plan
			continue

		console.log "Done checking #{plan.planId} - #{plan.state}"

	if questionableOutputList?.length > 0
		process.stdout.write '\n'
		for questionableOutput in questionableOutputList
			process.stdout.write "#{questionableOutput.planId},#{questionableOutput.state}\n"
			fs.unlinkSync plan2FilePath questionableOutput

	if noneAvailableOutputList?.length > 0
		for noneAvailableOutput in noneAvailableOutputList
			fs.unlinkSync plan2FilePath noneAvailableOutput
