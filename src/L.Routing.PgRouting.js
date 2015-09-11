(function() {
	'use strict';

	var L = require('leaflet');
	var corslite = require('corslite');

	L.Routing = L.Routing || {};

	L.Routing.PgRouting = L.Class.extend({
		options: {
			serviceUrl: 'http://localhost:8080/geoserver/pgrouting/wfs',
			timeout: 30 * 1000,
			urlParameters: {
				version: '1.0.0',
				request: 'GetFeature',
				outputFormat: 'application/json'
			}
		},

		initialize: function(typeName, options) {
			this._typeName = typeName;
			L.Util.setOptions(this, options);
		},

		route: function(waypoints, callback, context, options) {
			var timedOut = false,
				wps = [],
				url,
				timer,
				wp,
				i;

			options = options || {};
			url = this.buildRouteUrl(waypoints, options);

			timer = setTimeout(function() {
								timedOut = true;
								callback.call(context || callback, {
									status: -1,
									message: 'pgRouting GeoServer WFS request timed out.'
								});
							}, this.options.timeout);

			// Create a copy of the waypoints, since they
			// might otherwise be asynchronously modified while
			// the request is being processed.
			for (i = 0; i < waypoints.length; i++) {
				wp = waypoints[i];
				wps.push({
					latLng: wp.latLng,
					name: wp.name,
					options: wp.options
				});
			}

			corslite(url, L.bind(function(err, resp) {
				var data;

				clearTimeout(timer);
				if (!timedOut) {
					if (!err) {
						data = JSON.parse(resp.responseText);
						this._routeDone(data, wps, callback, context);
					} else {
						callback.call(context || callback, {
							status: -1,
							message: 'HTTP request failed: ' + err
						});
					}
				}
			}, this));

			return this;
		},

		_routeDone: function(response, inputWaypoints, callback, context) {
			var alts = [],
				totalDistance = 0,
				totalTime = 0,
				routeCoords = [],
				viaCoords = [],
				viaIndices = [],
				edgeCoords,
				i,
				feature,
				actualWaypoints;

			context = context || callback;
			/*
			if (response.info.errors && response.info.errors.length) {
				callback.call(context, {
					// TODO: include all errors
					status: response.info.errors[0].details,
					message: response.info.errors[0].message
				});
				return;
			}
			*/

			for (i = 0; i < response.features.length; i++) {
				feature = response.features[i];
				edgeCoords = this._coordsToLatLngs(feature.geometry.coordinates);
				if ((feature.properties.pointType & 1) || (feature.properties.pointType & 4)) {
					viaCoords.push(edgeCoords[0]);
					viaIndices.push(routeCoords.length);
				}
				if (feature.properties.pointType & 2) {
					viaCoords.push(edgeCoords[edgeCoords.length - 1]);
					viaIndices.push(routeCoords.length + edgeCoords.length - 1);
				}
				routeCoords = routeCoords.concat(edgeCoords);
				totalDistance += feature.properties.distance;
				totalTime += feature.properties.cost * 3600;
			}

			actualWaypoints = this._toWaypoints(inputWaypoints, viaCoords);

			alts.push({
				name: '',
				coordinates: routeCoords,
				instructions: this._convertInstructions(response.features),
				summary: {
					totalDistance: totalDistance,
					totalTime: totalTime
				},
				inputWaypoints: inputWaypoints,
				waypoints: actualWaypoints,
				waypointIndices: viaIndices
			});

			callback.call(context, null, alts);
		},

		_coordsToLatLngs: function(coords) {
			var latlngs = [],
				i;

			for (i = 0; i < coords.length; i++) {
				latlngs.push(new L.LatLng(coords[i][1], coords[i][0]));
			}

			return latlngs;
		},

		_toWaypoints: function(inputWaypoints, viaCoords) {
			var wps = [],
				i;
			for (i = 0; i < viaCoords.length; i++) {
				wps.push({
					latLng: viaCoords[i],
					name: inputWaypoints[i].name,
					options: inputWaypoints[i].options
				});
			}

			return wps;
		},

		buildRouteUrl: function(waypoints, options) {
			var points = [],
				i,
				baseUrl;
			
			for (i = 0; i < waypoints.length; i++) {
				points.push(waypoints[i].latLng.lng + '\\,' + waypoints[i].latLng.lat);
			}

			baseUrl = this.options.serviceUrl + L.Util.getParamString(L.extend({
					typeName: this._typeName,
					viewparams: 'points:' + points.join('|')
				}, this.options.urlParameters), baseUrl);

			return baseUrl;
		},

		_convertInstructions: function(features) {
			var result = [],
				i,
				props;

			for (i = 0; i < features.length; i++) {
				props = features[i].properties;
				result.push({
					type: '', // TODO:
					text: props.name,
					distance: props.distance,
					time: props.cost * 3600,
					index: 0, // TODO:
					exit: 0 // TODO:
				});
			}

			return result;
		}
	});

	L.Routing.pgRouting = function(typeName, options) {
		return new L.Routing.PgRouting(typeName, options);
	};

	module.exports = L.Routing.PgRouting;
})();
