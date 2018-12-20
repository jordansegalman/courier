var express = require('express');
var http = require('http');

// Load environment variables
require('dotenv').config();

const port = process.env.PORT;

// Setup Express and HTTP server
var app = express();
var httpServer = http.createServer(app);

// Setup Socket.IO
var io = require('socket.io')(httpServer);
var keySockets = {};	// Stores sender sockets with transaction keys

// Called when a Socket.IO client connects
io.on('connection', (socket) => {
	// Called when Socket.IO client disconnects
	socket.on('disconnect', () => {
	});
	// Called when sender requests to start sending
	socket.on('requestStartSend', (data, fn) => {
		// Generate random nine digit key for transaction
		var key = Math.random().toString().slice(2, 11);
		while (keySockets.hasOwnProperty(key)) {
			key = Math.random().toString().slice(2, 11);
		}
		// Add sender socket to keySockets with generated key
		keySockets[key] = socket;
		// Reply to sender with key
		fn(key);
	});
	// Called when receiver requests to start receiving
	socket.on('requestStartReceive', (data, fn) => {
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Request sender with given key to start sending data
			keySockets[key].emit('requestStartSend', {}, (data) => {
				// Reply to receiver with data
				fn(data);
			});
		} else {
			// Reply to receiver with nothing
			fn();
		}
	});
	// Called when receiver requests additional data
	socket.on('requestReceive', (data, fn) => {
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Request sender with given key to send additional data
			keySockets[key].emit('requestSend', {}, (data) => {
				// Reply to receiver with data
				fn(data);
			});
		} else {
			// Reply to receiver with nothing
			fn();
		}
	});
	// Called when receiver successfully received all data
	socket.on('received', (data) => {
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Notify sender that receiver successfully received all data
			keySockets[key].emit('received', {});
			// Delete sender socket from keySockets with given key
			delete keySockets[key];
		}
	});
});

// Listen on port
httpServer.listen(port, function (error) {
	if (error) throw error;
	console.log('Server listening on port ' + port + '.');
});
