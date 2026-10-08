# Budget configuration ---------------------------------------------------

get_monthly_allocations <- function() {
  tibble::tribble(
    ~budget_category, ~monthly_allocation,
    "Housing & related expenses", 2820,
    "Transportation", 500,
    "Food & living expenses", 1230,
    "Personal & discretionary", 1100,
    "Rainy day & irregular expenses", 650
  )
}

get_merchant_category_rules <- function() {
  tibble::tribble(
    ~rule_priority, ~rule_name, ~description_pattern, ~budget_category,
    10, "mortgage", "^(UNITEDWHOLESALE LOAN PAYMT|UWM ACH|BILT FOR UWM)", "Housing & related expenses",
    20, "rent", "^ZELLE TO BARNEY REGISTER", "Housing & related expenses",
    30, "natural_gas", "^(QUESTARGAS|ENBRIDGE GAS)", "Housing & related expenses",
    40, "city_utilities", "^PROVO CITY UTILITIES", "Housing & related expenses",
    50, "internet", "^(GFIBER|GOOGLE FIBER)", "Housing & related expenses",
    60, "home_warranty", "^ACCLAIMED HOME WARRANTY", "Housing & related expenses",
    100, "sams_club_gas", "SAMSCLUB.*GAS", "Transportation",
    110, "fuel_stations", "^(PILOT|ARCO|CHEVRON|STINKER|MAVERIK|SHELL|SMITHS-FUEL|FRED M FUEL|PHILLIPS 66)", "Transportation",
    120, "routine_vehicle_service", "^(LES SCHWAB|AUTOZONE|INSPECTION STATION|GOODYEAR)", "Transportation",
    130, "road_tolls", "^FASTRAK", "Transportation",
    200, "warehouse_groceries", "^(SAMSCLUB|SAMS CLUB)", "Food & living expenses",
    210, "supermarkets", "^(TRADER JOE|WAL-MART|WM SUPERCENTER|FRED MEYER|SAFEWAY|SUPERVALU|SMITHS FOOD|HOLIDAY MARKET|WHOLEFDS|ALBERTSONS)|WINCO FOODS", "Food & living expenses",
    220, "pharmacy_and_medical", "^(WALGREENS|KP NCAL)", "Food & living expenses",
    230, "postal_expenses", "^USPS", "Food & living expenses",
    300, "major_auto_repair", "^GEORGE'S FRIENDLY AUTO", "Rainy day & irregular expenses",
    400, "variable_retailers", "^(VENMO PAYMENT|VENMO PURCHASE|APPLE|TARGET|THE HOME DEPOT|UTAH FIRST CREDIT UNIO|STAPLES|SHERWIN-WILLIAMS|AMAZON|PETSMART)", "Personal & discretionary",
    410, "clothing_and_personal_retail", "^(ZARA USA|H&M|UNIQLO|SEPHORA)", "Personal & discretionary",
    420, "personal_airfare", "^(BRITISH AWYS|SOUTHWES|DELTA|UNITED [0-9]|FRONTIER AI|ALASKA AIR|AMERICAN AIR|EDREAMS)", "Personal & discretionary",
    430, "personal_travel", "^(WESTIN|FAIRFIELD INN|FREENOW|THE RITZ-CARLTON|TSA PRECHECK|FOREIGN CURRENCY CONVERSION FEE|ALLIANZ TRAVEL INS)|AIRPORT PARKNG", "Personal & discretionary",
    440, "restaurants", "^(HOUSE KITCHEN AND BAR|PANDA EXPRESS|CAFE RIO|RED'S PIZZERIA|DD \\*DOORDASH|CHEESECAKE|SLIM CHICKENS|LOS BETOS|SAMMIES RESTAURANT|CULVERS|CHIPOTLE|TAVERN AT EAGLE ISLAND|TST\\* WEST COAST SOURDOUGH|RAILROAD FISH & CHIPS)", "Personal & discretionary",
    450, "recreation_and_subscriptions", "^(SP BE ULTIMATE|USA ULTIMATE|ULTIWORLD|AUDLTV|VIVID SEATS|BARNES & NOBLE|DICKS SPORTING GOODS|PAYPAL \\*ATOLEA|CLEANINGTHEGLASS|SACRAMENTO ZOO|TAKE CARE BARBERSHOP|SOAR & STEEL|TANGLE NEWS|VAULT SALON)", "Personal & discretionary"
  )
}
