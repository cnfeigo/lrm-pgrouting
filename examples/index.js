var map = L.map('map');

L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {
	attribution: '&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);

L.Routing.control({
	waypoints: [
		L.latLng(34.944479, 135.702857),
		L.latLng(34.944916, 135.702972),
		L.latLng(34.944530, 135.703476)
	],
	geocoder: L.Control.Geocoder.nominatim(),
	router: L.Routing.pgRouting('muko'),
	routeWhileDragging: false,
	reverseWaypoints: true
}).addTo(map);
