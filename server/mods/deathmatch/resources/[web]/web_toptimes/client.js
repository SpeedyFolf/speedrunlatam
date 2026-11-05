// https://stackoverflow.com/questions/17929356/html-datalist-values-from-array-in-javascript
// https://stackoverflow.com/questions/46014167/how-i-can-get-the-value-from-datalist
// https://www.w3schools.com/jsref/met_win_settimeout.asp
// https://www.w3schools.com/cssref/pr_class_display.asp

function updateInfo() {
	getAllToptimesInfo (
		function (value) {
			var options = '';
			var mapListElement = document.getElementById("mapList");
			for (var i=0; i<value.length-1; i++) {
				options += '<option value="' + value[i] + '"></option>';
			}
			mapListElement.innerHTML = options;
			if (options == "")
				document.getElementById("mapInput").value = "There are no toptimes on any map on the server!";
			else
				document.getElementById("mapInput").value = "";
			document.getElementById("mapCountLabel").innerHTML = "Total map count: " + value[value.length-1];
			getMapInfo();
			setTimeout(function(){document.getElementById("container").style.display = "inherit";}, 150);
		}
	);
}

function getMapInfo() {
	var mapInputElement = document.getElementById("mapInput");
	getMapToptimesInfo (mapInputElement.value,
		function (value) {
			console.log(value);
			
			// Map author label
			var mapAuthorLabelElement = document.getElementById("mapAuthorLabel");
			mapAuthorLabelElement.innerHTML = "Map author: " + value["mapAuthor"];
			
			// Total top times label
			var totalTopsLabelElement = document.getElementById("totalTopsLabel");
			totalTopsLabelElement.innerHTML = "Total toptimes: " + (value["times"].length);
			
			var tableElement = document.getElementById("mapInfoTbody");
			tableElement.innerHTML = ""
			
			for (let i = 0; i < value["times"].length; i++) {
				let time = value["times"][i];
				tableElement.innerHTML += "<tr>"
					+ "<td>" + (i+1) + "</td>"
					+ "<td>" + time.playerName + "</td>"
					+ "<td>" + (mapInputElement.value == "" ? "" : convertTime(time.time)) + "</td>"
					+ "<td>" + (mapInputElement.value == "" ? "" : ("+" + convertTime(time.time - value["times"][0].time))) + "</td>"
					+ "<td>" + convertDate(time.dateRecorded) + "</td>"
					+ "</tr>"
				;
			}
		}
	);
}

function clearInputField() {
	document.getElementById("mapInput").value = "";
	document.getElementById("mapInput").focus();
	getMapInfo();
}

function convertTime(totalMs, leaveBlankIfZero = true) {
	// if ((!totalMs) || (totalMs == "")) return leaveBlankIfZero ? "" : "0:00.000";
	
	let ms = (totalMs % 1000).toString().padStart(3, '0');
	let second = (Math.floor((totalMs/1000) % 60)).toString().padStart(2, '0');
	let minute = Math.floor(totalMs/(60000));

	return `${minute}:${second}.${ms}`;
}

function convertDate(timestamp) {
	if ((!timestamp) || (timestamp == "")) return "";

	let date = new Date(timestamp * 1000);
	let year = date.getFullYear();
	let month = (date.getMonth()+1).toString().padStart(2, '0');
	let day = date.getDate().toString().padStart(2, '0');

	return `${year}-${month}-${day}`;
}