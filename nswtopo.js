function initMap() {
    var showAbout = document.getElementById('show-about')
    var about = document.getElementById('about');
    var title = document.getElementById('title');
    var toggles = document.getElementById('toggles');
    var qrcode = document.getElementById('qrcode');
    var touch = 'ontouchstart' in document.documentElement;
    var map = new google.maps.Map(document.getElementById('map'), {
        mapTypeId: google.maps.MapTypeId.TERRAIN,
        streetViewControl: false,
    });
    map.data.loadGeoJson('maps.json', {}, function(features) {
        var states = [];
        var types = [];
        var bounds = new google.maps.LatLngBounds();
        features.forEach(function(feature) {
            feature.getGeometry().getAt(0).getArray().forEach(function(point) {
                bounds.extend(point);
            })
            if (types.indexOf(feature.getProperty('type')) < 0)
                types.push(feature.getProperty('type'));
            if (feature.getProperty('type') === 'bundle') return;
            if (states.indexOf(feature.getProperty('state')) < 0)
                states.push(feature.getProperty('state'));
        });
        map.fitBounds(bounds);
        states.forEach(function(state) {
            var element = document.createElement('div');
            element.textContent = state;
            element.id = 'show-' + state;
            element.classList.add('selected');
            toggles.appendChild(element);
            element.addEventListener('click', function() {
                element.classList.toggle('selected');
                features.filter(function(feature) {
                    return document.getElementById('show-' + feature.getProperty('type')).classList.contains('selected');
                }).forEach(function(feature) {
                    var selected = feature.getProperty('state').split(',').some(function(state) {
                        return document.getElementById('show-' + state).classList.contains('selected');
                    });
                    map.data.overrideStyle(feature, { visible: selected });
                });
            });
        });
        types.forEach(function(type) {
            var element = document.createElement('div');
            element.textContent = type;
            element.id = 'show-' + type;
            element.classList.add('selected');
            toggles.appendChild(element);
            element.addEventListener('click', function() {
                var selected = element.classList.toggle('selected');
                features.filter(function(feature) {
                    return feature.getProperty('state').split(',').some(function(state) {
                        return document.getElementById('show-' + state).classList.contains('selected');
                    });
                }).filter(function(feature) {
                    return feature.getProperty('type') === type;
                }).forEach(function(feature) {
                    map.data.overrideStyle(feature, { visible: selected });
                });
            });
        });
    });
    map.data.setStyle(function(feature) {
        var type = feature.getProperty('type');
        var colour = type === '25k' ? '#FF0000' : type === '50k' ? '#0000FF' : '#000000';
        return {
            strokeColor: colour,
            fillColor: colour,
            strokeOpacity: 0.8,
            fillOpacity: type === 'bundle' ? 0.25 : 0.15,
            strokeWeight: 1,
        };
    });
    map.controls[google.maps.ControlPosition.RIGHT_CENTER].push(document.getElementById('toggles'));
    showAbout.addEventListener('click', function() {
        showAbout.classList.toggle('selected');
        about.classList.toggle('hidden');
    });
    map.data.addListener('click', function(event) {
        window.open(event.feature.getProperty('url'));
    });
    map.data.addListener('mouseover', function(event) {
        map.data.overrideStyle(event.feature, { strokeWeight: 4});
        var span = document.createElement('span');
        span.textContent = event.feature.getProperty('title');
        title.appendChild(span);
        if (touch) return;
        new QRCode(qrcode, {
            text: event.feature.getProperty('url'),
            width: 128,
            height: 128,
        });
        qrcode.classList.toggle('hidden');
    });
    map.data.addListener('mouseout', function(event) {
        map.data.overrideStyle(event.feature, { strokeWeight: 1});
        title.innerHTML = null;
        if (touch) return;
        qrcode.innerHTML = null;
        qrcode.classList.toggle('hidden');
    });
    function hideAbout() {
        showAbout.classList.remove('selected');
        about.classList.add('hidden');
    }
    google.maps.event.addDomListener(map, 'mousedown', hideAbout);
    map.data.addListener('mousedown', hideAbout);
    document.getElementById('close').addEventListener('click', hideAbout);
}
