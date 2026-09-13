let searchSetup = false;
let fuse;

async function initIndex() {
	if (searchSetup) return;

	const url = document.getElementById("search-index").textContent;
	const response = await fetch(url);

	if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

	const options = {
		includeScore: false,
		includeMatches: true,
		ignoreLocation: true,
		threshold: 0.15,
		keys: [
			{ name: "title", weight: 3 },
			{ name: "description", weight: 2 },
			{ name: "body", weight: 1 }
		]
	};

	fuse = new Fuse(await response.json(), options);
	searchSetup = true;

	console.log("Search index initialized successfully");
}

async function toggleSearch() {
	await initIndex();
	const searchBar = document.getElementById("search-bar");
	const searchContainer = document.getElementById("search-container");
	searchContainer.classList.toggle("active");
	searchBar.toggleAttribute("disabled");
	searchBar.focus();
}

function debounce(actual_fn, wait) {
	let timeoutId;

	return (...args) => {
		clearTimeout(timeoutId);
		timeoutId = setTimeout(() => {
			actual_fn(...args);
		}, wait);
	};
}

function initSearch() {
	const searchBar = document.getElementById("search-bar");
	const searchContainer = document.getElementById("search-container");
	const searchResults = document.getElementById("search-results");
	const MAX_ITEMS = 10;
	const MAX_RESULTS = 4;

	function makeTeaser(result, searchVal) {
		const TEASER_SIZE = 20;
		const resultDiv = document.createElement("div");
		resultDiv.className = "search-result item";

		const titleLink = document.createElement("a");
		titleLink.className = "result-title";
		titleLink.href = result.item.url;
		titleLink.textContent = result.item.title;
		resultDiv.appendChild(titleLink);

		for (const match of result.matches) {
			if (match.key === "title") continue;

			const indices = match.indices
				.sort((a, b) => Math.abs(a[1] - a[0] - searchVal.length) - Math.abs(b[1] - b[0] - searchVal.length))
				.slice(0, MAX_RESULTS);
			const value = match.value;

			for (const ind of indices) {
				const start = Math.max(0, ind[0] - TEASER_SIZE);
				const end = Math.min(value.length - 1, ind[1] + TEASER_SIZE);

				const span = document.createElement("span");
				span.appendChild(document.createTextNode(value.substring(start, ind[0])));

				const strong = document.createElement("strong");
				strong.textContent = value.substring(ind[0], ind[1] + 1);
				span.appendChild(strong);

				span.appendChild(document.createTextNode(value.substring(ind[1] + 1, end)));
				resultDiv.appendChild(span);
			}

			if (match.indices.length > MAX_RESULTS) {
				const moreSpan = document.createElement("span");
				moreSpan.className = "more-matches";
				const moreMatchesText = document.getElementById("more-matches-text").textContent;
				moreSpan.textContent = moreMatchesText.replace("$MATCHES", `+${match.indices.length - MAX_RESULTS}`);
				resultDiv.appendChild(moreSpan);
			}
		}
		return resultDiv;
	}

	const performSearch = debounce(() => {
		if (!fuse) return;

		const searchVal = searchBar.value.trim();
		const results = fuse.search(searchVal, { limit: MAX_ITEMS });

		searchResults.innerHTML = "";
		for (const result of results) {
			searchResults.appendChild(makeTeaser(result, searchVal));
		}

		searchResults.style.display = results.length > 0 ? "flex" : "none";
	}, 300);

	searchBar.addEventListener("keyup", performSearch);

	document.addEventListener("click", function (event) {
		if (searchSetup && searchBar.getAttribute("disabled") === null && !searchContainer.contains(event.target)) {
			toggleSearch();
		}
	}, { passive: true });

	document.addEventListener("keydown", function (event) {
		if (event.key === "/") {
			event.preventDefault();
			toggleSearch();
		}
	});

	document.getElementById("search-toggle").addEventListener("click", toggleSearch);
}

if (document.readyState === "complete" ||
	(document.readyState !== "loading" && !document.documentElement.doScroll))
	initSearch();
else
	document.addEventListener("DOMContentLoaded", initSearch);