package utils

import (
	"errors"
	"regexp"
	"strings"
)

// Canonical two-letter USPS codes for states, territories, and military/diplomatic mail.
const (
	StateAL = "AL"
	StateAK = "AK"
	StateAZ = "AZ"
	StateAR = "AR"
	StateCA = "CA"
	StateCO = "CO"
	StateCT = "CT"
	StateDE = "DE"
	StateFL = "FL"
	StateGA = "GA"
	StateHI = "HI"
	StateID = "ID"
	StateIL = "IL"
	StateIN = "IN"
	StateIA = "IA"
	StateKS = "KS"
	StateKY = "KY"
	StateLA = "LA"
	StateME = "ME"
	StateMD = "MD"
	StateMA = "MA"
	StateMI = "MI"
	StateMN = "MN"
	StateMS = "MS"
	StateMO = "MO"
	StateMT = "MT"
	StateNE = "NE"
	StateNV = "NV"
	StateNH = "NH"
	StateNJ = "NJ"
	StateNM = "NM"
	StateNY = "NY"
	StateNC = "NC"
	StateND = "ND"
	StateOH = "OH"
	StateOK = "OK"
	StateOR = "OR"
	StatePA = "PA"
	StateRI = "RI"
	StateSC = "SC"
	StateSD = "SD"
	StateTN = "TN"
	StateTX = "TX"
	StateUT = "UT"
	StateVT = "VT"
	StateVA = "VA"
	StateWA = "WA"
	StateWV = "WV"
	StateWI = "WI"
	StateWY = "WY"
	StateDC = "DC"
	StatePR = "PR"
	StateGU = "GU"
	StateVI = "VI"
	StateAS = "AS"
	StateMP = "MP"
	StateUM = "UM"
	StateAA = "AA"
	StateAE = "AE"
	StateAP = "AP"
)

// ErrInvalidState is returned when NormalizeUSState is given an unknown value.
var ErrInvalidState = errors.New("invalid US state or territory")

var nonAlphaNum = regexp.MustCompile(`[^A-Z0-9]+`)

// stateMap maps a variety of common inputs (without punctuation) to canonical codes.
var stateMap = map[string]string{
	"AL": StateAL, "ALABAMA": StateAL, "ALA": StateAL,
	"AK": StateAK, "ALASKA": StateAK,
	"AZ": StateAZ, "ARIZONA": StateAZ, "ARIZ": StateAZ,
	"AR": StateAR, "ARKANSAS": StateAR, "ARK": StateAR,
	"CA": StateCA, "CALIFORNIA": StateCA, "CALIF": StateCA, "CAL": StateCA,
	"CO": StateCO, "COLORADO": StateCO, "COLO": StateCO,
	"CT": StateCT, "CONNECTICUT": StateCT, "CONN": StateCT,
	"DE": StateDE, "DELAWARE": StateDE, "DEL": StateDE,
	"FL": StateFL, "FLORIDA": StateFL, "FLA": StateFL,
	"GA": StateGA, "GEORGIA": StateGA,
	"HI": StateHI, "HAWAII": StateHI,
	"ID": StateID, "IDAHO": StateID,
	"IL": StateIL, "ILLINOIS": StateIL, "ILL": StateIL,
	"IN": StateIN, "INDIANA": StateIN, "IND": StateIN,
	"IA": StateIA, "IOWA": StateIA,
	"KS": StateKS, "KANSAS": StateKS, "KAN": StateKS,
	"KY": StateKY, "KENTUCKY": StateKY,
	"LA": StateLA, "LOUISIANA": StateLA,
	"ME": StateME, "MAINE": StateME,
	"MD": StateMD, "MARYLAND": StateMD,
	"MA": StateMA, "MASSACHUSETTS": StateMA, "MASS": StateMA,
	"MI": StateMI, "MICHIGAN": StateMI, "MICH": StateMI,
	"MN": StateMN, "MINNESOTA": StateMN, "MINN": StateMN,
	"MS": StateMS, "MISSISSIPPI": StateMS, "MISS": StateMS,
	"MO": StateMO, "MISSOURI": StateMO,
	"MT": StateMT, "MONTANA": StateMT, "MONT": StateMT,
	"NE": StateNE, "NEBRASKA": StateNE, "NEB": StateNE, "NEBR": StateNE,
	"NV": StateNV, "NEVADA": StateNV, "NEV": StateNV,
	"NH": StateNH, "NEWHAMPSHIRE": StateNH,
	"NJ": StateNJ, "NEWJERSEY": StateNJ,
	"NM": StateNM, "NEWMEXICO": StateNM,
	"NY": StateNY, "NEWYORK": StateNY,
	"NC": StateNC, "NORTHCAROLINA": StateNC,
	"ND": StateND, "NORTHDAKOTA": StateND,
	"OH": StateOH, "OHIO": StateOH,
	"OK": StateOK, "OKLAHOMA": StateOK, "OKLA": StateOK,
	"OR": StateOR, "OREGON": StateOR, "ORE": StateOR, "OREG": StateOR,
	"PA": StatePA, "PENNSYLVANIA": StatePA, "PENN": StatePA,
	"RI": StateRI, "RHODEISLAND": StateRI,
	"SC": StateSC, "SOUTHCAROLINA": StateSC,
	"SD": StateSD, "SOUTHDAKOTA": StateSD,
	"TN": StateTN, "TENNESSEE": StateTN, "TENN": StateTN,
	"TX": StateTX, "TEXAS": StateTX, "TEX": StateTX,
	"UT": StateUT, "UTAH": StateUT,
	"VT": StateVT, "VERMONT": StateVT,
	"VA": StateVA, "VIRGINIA": StateVA,
	"WA": StateWA, "WASHINGTON": StateWA, "WASH": StateWA,
	"WV": StateWV, "WESTVIRGINIA": StateWV, "WVA": StateWV,
	"WI": StateWI, "WISCONSIN": StateWI, "WIS": StateWI, "WISC": StateWI,
	"WY": StateWY, "WYOMING": StateWY, "WYO": StateWY,
	"DC": StateDC, "DISTRICTOFCOLUMBIA": StateDC,
	"PR": StatePR, "PUERTORICO": StatePR,
	"GU": StateGU, "GUAM": StateGU,
	"VI": StateVI, "VIRGINISLANDS": StateVI, "USVI": StateVI,
	"AS": StateAS, "AMERICANSAMOA": StateAS, "AMSAM": StateAS,
	"MP": StateMP, "CNMI": StateMP, "NMARIANAS": StateMP,
	"UM": StateUM, "UMOI": StateUM,
	"AA": StateAA, "ARMEDFORCESAMERICASEXCEPTCANADA": StateAA,
	"AE": StateAE, "ARMEDFORCESEUROPEMIDDLEEASTAFRICACANADA": StateAE,
	"AP": StateAP, "ARMEDFORCESPACIFIC": StateAP,
}

// NormalizeUSState returns the canonical two-letter USPS code for the given input.
// The function is case-insensitive and ignores punctuation and whitespace.
func NormalizeUSState(s string) (string, error) {
	cleaned := strings.ToUpper(s)
	cleaned = nonAlphaNum.ReplaceAllString(cleaned, "")
	if code, ok := stateMap[cleaned]; ok {
		return code, nil
	}
	return "", ErrInvalidState
}
