extends RefCounted
## Shared menu, lobby and runtime map catalogue.
const IDS: Array[String] = ["desert_town", "forest_facility", "urban_docks", "freight_yard", "snow_outpost"]
const ENTRIES := [
	{"id": "desert_town", "name": "Desert Town", "description": "Sandy streets, long sightlines and tight market alleys."},
	{"id": "forest_facility", "name": "Forest Facility", "description": "Forested hills, concrete bunkers and a radar installation."},
	{"id": "urban_docks", "name": "Urban Docks", "description": "Container lanes and close combat on the waterfront."},
	{"id": "freight_yard", "name": "Freight Yard", "description": "Rail sidings, container flanks and an enterable warehouse."},
	{"id": "snow_outpost", "name": "Snow Outpost", "description": "Snowbound bunkers around a communications courtyard."},
]
