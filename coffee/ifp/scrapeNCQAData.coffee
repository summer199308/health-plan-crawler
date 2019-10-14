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
Horseman = require "node-horseman"

WAIT_TIME = process.env.OPT_WAIT_TIME || 1000
WAIT_TIME = parseInt WAIT_TIME

startedPageUrl = 'http://healthinsuranceratings.ncqa.org/2018/Default.aspx'

module.exports = scrapeNCQAData = (cb) ->

	horseman = new Horseman
		timeout : 60000
		loadImages : false
		switchToNewTab : true
		# webSecurity: true
		# ignoreSSLErrors: true

	done = ->
		horseman.close()

	await horseman.viewport 1024, 1600
	.open startedPageUrl
	.catch (err) ->
		console.error err
		console.log "Error happened after #{zipTimer}ms"
		console.log "Failed to open the started page initially"
		done()
		cb()

	allPagesStatus = {}

	await processCurrentPageContent horseman
	console.log "Process page - 1"
	allPagesStatus['1'] = true

	hasMorePages = true
	while hasMorePages
		pages = await loadPageList horseman
		for nextPage from pickPageNumToProcess(pages)
			continue if allPagesStatus[nextPage]
			console.log "Process page - #{nextPage}"
			# console.log pages[nextPage]
			await goToPage horseman, nextPage, pages[nextPage].index
			await processCurrentPageContent horseman
			allPagesStatus[nextPage] = true

		morePagesBtn = pages['...']
		hasMorePages = morePagesBtn?
		if hasMorePages
			pageTobeProcessed = _.keys(allPagesStatus).length + 1
			await goToPage horseman, pageTobeProcessed, morePagesBtn.index
			console.log "Process page - #{pageTobeProcessed}"
			await processCurrentPageContent horseman
			allPagesStatus[pageTobeProcessed] = true


	done()
	cb()

processCurrentPageContent = (horseman) ->
	await horseman.html 'div#divAccount'
	.then (table) ->
		console.log table # TODO

goToPage = (horseman, pageNum, pageIndex) ->
	await horseman.log "Go to page #{pageNum}"
	.click "div#divAccount table.displaytable tbody tr:last td:nth-child(#{pageIndex}) a"
	.catch (err) ->
		console.error err
		console.log "Failed to click page #{pageNum}"
	.waitForNextPage {timeout: 120000}
	.catch (err) ->
		console.error err
		console.log "Failed to open page #{pageNum}"

loadPageList = (horseman) ->
	pages = {}
	await horseman.log "Load page list"
	.evaluate (selector) ->
		results = []
		i = 0
		$(selector).find('td').each ->
			i++
			that = $(@)
			pageNum = that.text()
			results.push
				num: pageNum
				hasLink: that.children('a').length
				index: i
		return results
	, 'div#divAccount table.displaytable tbody tr:last'
	.then (results) ->
		for page in results
			continue if /[a-zA-Z]+/i.test page.num
			continue if page.num is '...' and page.index is 2
			pages[page.num] =
				processed: page.hasLink is 0
				index: page.index

	# console.log pages

	return pages

pickPageNumToProcess = (pages) ->
	allAvailablePage = _.pickBy pages, (info) -> info.processed is false
	allAvailablePage = _.keys allAvailablePage
	allAvailablePage = _.filter allAvailablePage, (pageNum) ->
		pageNum = parseInt pageNum
		return not isNaN pageNum
	allAvailablePage = _.sortBy allAvailablePage, parseInt

	for page in allAvailablePage
		yield page


if process.argv[1] and process.argv[1].match(__filename)
	scrapeNCQAData ->
		console.log "Done"
		process.exit 0
