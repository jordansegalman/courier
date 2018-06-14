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
var keySockets = {};
io.on('connection', (socket) => {
	console.log('Socket.IO connection');
	socket.on('disconnect', () => {
		console.log('Socket.IO disconnection');
	});
	socket.on('requestStartSend', (data, fn) => {
		var key = Math.random().toString().slice(2, 11);
		while (keySockets.hasOwnProperty(key)) {
			key = Math.random().toString().slice(2, 11);
		}
		console.log('from requestStartSend');
		keySockets[key] = socket;
		fn(key);
	});
	socket.on('requestStartReceive', (data, fn) => {
		var key = data.key;
		if (keySockets.hasOwnProperty(key)) {
		console.log('from requestStartReceive');
			keySockets[key].emit('requestStartSend', {}, (data) => {
		console.log('reply requestStartSend');
				fn(data);
			});
		} else {
			fn();
		}
	});
	var i = 0;
	socket.on('requestReceive', (data, fn) => {
		var key = data.key;
		if (keySockets.hasOwnProperty(key)) {
		console.log('from requestReceive');
			keySockets[key].emit('requestSend', {}, (data) => {
		console.log('reply requestSend');
				console.log(i++);
				fn(data);
			});
		} else {
			fn();
		}
	});
	socket.on('received', (data) => {
		var key = data.key;
		if (keySockets.hasOwnProperty(key)) {
		console.log('from received');
			keySockets[key].emit('received', {});
			delete keySockets[key];
		}
	});
});

// Listen on port
httpServer.listen(port, function (error) {
	if (error) throw error;
	console.log('Server listening on port ' + port + '.');
});
