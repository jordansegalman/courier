var express = require('express');
var http = require('http');

// Load environment variables
require('dotenv').config();

const port = process.env.PORT;	// Server port
const keyLength = 9;		// Transaction key length

// Setup Express and HTTP server
var app = express();
var httpServer = http.createServer(app);

// Setup Socket.IO
var io = require('socket.io')(httpServer);
var keySockets = {};	// Stores sender sockets with transaction keys

// Called when a Socket.IO client connects
io.on('connection', (socket) => {
	console.log('Socket.IO on connection');
	// Called when Socket.IO client disconnects
	socket.on('disconnect', () => {
		console.log('Socket.IO on disconnect');
	});
	// Called when sender requests to start sending
	socket.on('requestStartSend', (data, fn) => {
		console.log('Socket.IO on requestStartSend');
		// Generate random key with keyLength digits for transaction
		var key = Math.random().toString().slice(2, 2 + keyLength);
		while (keySockets.hasOwnProperty(key)) {
			key = Math.random().toString().slice(2, 2 + keyLength);
		}
		// Add sender socket to keySockets with generated key
		keySockets[key] = socket;
		// Reply to sender with key
		console.log('Socket.IO reply requestStartSend');
		fn(key);
	});
	// Called when receiver requests to start receiving
	socket.on('requestStartReceive', (data, fn) => {
		console.log('Socket.IO on requestStartReceive');
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Request sender with given key to start sending data
			console.log('Socket.IO emit requestStartSend');
			keySockets[key].emit('requestStartSend', {}, (data) => {
				// Reply to receiver with data
				console.log('Socket.IO reply requestStartReceive');
				fn(data);
			});
		} else {
			// Reply to receiver with nothing
			console.log('Socket.IO reply requestStartReceive');
			fn();
		}
	});
	// Called when receiver requests additional data
	socket.on('requestReceive', (data, fn) => {
		console.log('Socket.IO on requestReceive');
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Request sender with given key to send additional data
			console.log('Socket.IO emit requestSend');
			keySockets[key].emit('requestSend', {}, (data) => {
				// Reply to receiver with data
				console.log('Socket.IO reply requestReceive');
				fn(data);
			});
		} else {
			// Reply to receiver with nothing
			console.log('Socket.IO reply requestReceive');
			fn();
		}
	});
	// Called when receiver successfully received all data
	socket.on('received', (data) => {
		console.log('Socket.IO on received');
		var key = data.key;
		// Check if given key is in keySockets
		if (keySockets.hasOwnProperty(key)) {
			// Notify sender that receiver successfully received all data
			console.log('Socket.IO emit received');
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
