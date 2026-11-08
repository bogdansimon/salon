#!/usr/bin/env bash
# Re-records the JSON fixtures used by SalonCoreTests from the live APIs,
# then scrubs them (API keys, personal paths) with scrub-fixtures.py.
#
#   scripts/record-fixtures.sh
#
# Optional: SALON_SI_KEY=<your api.data.gov key> (defaults to the public DEMO_KEY).
# The key is only used for the request; it never ends up in a fixture.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="SalonCoreTests/Fixtures"
UA="Salon/1.0 (+https://github.com/bogdansimon/salon)"
SI_KEY="${SALON_SI_KEY:-DEMO_KEY}"
mkdir -p "$OUT"

get() { # get <file> <url> [extra curl args...]
  local file="$1" url="$2"; shift 2
  echo "→ $file"
  curl -sfSL -A "$UA" "$@" "$url" -o "$OUT/$file"
}

# The Met — Wheat Field with Cypresses
get met_search.json "https://collectionapi.metmuseum.org/public/collection/v1.1/search?q=*&hasImages=true&medium=Paintings&isHighlight=true&limit=1&offset=0"
get met_object.json "https://collectionapi.metmuseum.org/public/collection/v1/objects/436535"

# Art Institute of Chicago — first boosted public-domain painting
get aic_search.json "https://api.artic.edu/api/v1/artworks/search" \
  -H 'Content-Type: application/json' -H "AIC-User-Agent: $UA" \
  -d '{"query":{"bool":{"filter":[{"term":{"is_public_domain":true}},{"terms":{"artwork_type_title.keyword":["Painting"]}},{"exists":{"field":"image_id"}},{"term":{"is_boosted":true}}]}},"limit":1,"page":1,"fields":["id","title","artist_display","date_display","medium_display","dimensions","image_id","thumbnail","description","short_description","is_public_domain"]}'

# Cleveland Museum of Art
get cma_search.json "https://openaccess-api.clevelandart.org/api/artworks/?type=Painting&cc0=1&has_image=1&highlight=1&limit=1&skip=5"

# Rijksmuseum — first and last search page (catalogue walk), one object
get rijks_search_first.json "https://data.rijksmuseum.nl/search/collection?type=painting&imageAvailable=true"
LAST=$(python3 -c "import json,sys;print(json.load(open('$OUT/rijks_search_first.json'))['partOf']['last']['id'])")
get rijks_search_last.json "$LAST"
get rijks_object.json "https://id.rijksmuseum.nl/200105887" -H 'Accept: application/ld+json'

# SMK — National Gallery of Denmark
get smk_search.json "https://api.smk.dk/api/v1/art/search/?keys=*&filters=%5Bhas_image:true%5D,%5Bpublic_domain:true%5D,%5Bobject_names:painting%5D&offset=7&rows=10&lang=en"

# Wikidata / Wikimedia Commons / Wikipedia — Officer and Laughing Girl (Frick Collection)
get wikidata_sparql.json "https://query.wikidata.org/sparql?format=json&query=SELECT%20%3Fp%20%3Fimg%20%3Fsl%20WHERE%20%7B%20VALUES%20%3Fp%20%7B%20wd%3AQ12418%20wd%3AQ151047%20wd%3AQ467376%20%7D%20%3Fp%20wdt%3AP18%20%3Fimg%3B%20wikibase%3Asitelinks%20%3Fsl%20.%20%7D"
get wikidata_entity.json "https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=Q467376&props=labels%7Cclaims%7Csitelinks&languages=en&sitefilter=enwiki"
get wikidata_labels.json "https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&ids=Q41264%7CQ682827%7CQ296955&props=labels&languages=en"
get commons_imageinfo.json "https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Csize%7Cextmetadata&iiextmetadatafilter=LicenseShortName&iiurlwidth=4096&titles=File:Johannes%20Vermeer%20-%20De%20Soldaat%20en%20het%20Lachende%20Meisje%20-%20Google%20Art%20Project.jpg"
get wikipedia_summary.json "https://en.wikipedia.org/api/rest_v1/page/summary/Officer_and_Laughing_Girl"

# Smithsonian Open Access (needs a key; DEMO_KEY works for a handful of calls)
get si_search.json "https://api.si.edu/openaccess/api/v1.0/search?q=online_media_type:%22Images%22+AND+object_type:%22Paintings%22&rows=1&start=200&api_key=$SI_KEY"

python3 scripts/scrub-fixtures.py "$OUT"
echo "Done. Review 'git diff $OUT' before committing."
