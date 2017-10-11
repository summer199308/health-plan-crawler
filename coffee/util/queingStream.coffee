async = require 'async'

###
    options:
    	stream:
    	task: # the on 'data' task defined as (task,cb), where task contains property 'data'
    	concurrency: # the number of concurrent records that can be processed

    cb invoked when stream is finished being read
###
queueingStream = (options, cb) ->
	{stream, task, concurrency} = options

	queue = async.queue task, concurrency

	queue.drain = ->
		stream.resume()

	stream.on 'data', (data) ->
		stream.pause()

		queue.push
			data: data

	stream.on 'error', (err) ->
		cb(err)


	stream.on 'end', ->
		if queue.length() is 0
			cb()
		else
			queue.drain = ->
				cb()


module.exports = queueingStream
