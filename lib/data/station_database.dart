import '../services/distance_calculator.dart';
import '../services/geocoding_service.dart';

/// Curated offline database of major Indian railway stations, metro junctions,
/// and transit hubs for STOP Vanthachu.
///
/// Enables seamless offline searching, route planning, and reverse-geocoding
/// in remote areas, tunnels, or offline transit conditions.
class LocalStationDatabase {
  LocalStationDatabase._();

  static const List<GeocodedPlace> stations = [
    // Tamil Nadu / Chennai
    GeocodedPlace(
      name: 'Chennai Central (MAS)',
      address: 'Kannappar Thidal, Periyamet, Chennai, Tamil Nadu 600003',
      latitude: 13.0827,
      longitude: 80.2707,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Chennai Egmore (MS)',
      address: 'Egmore, Chennai, Tamil Nadu 600008',
      latitude: 13.0797,
      longitude: 80.2612,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Tambaram (TBM)',
      address: 'Tambaram, Chennai, Tamil Nadu 600045',
      latitude: 12.9249,
      longitude: 80.1000,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Guindy Metro & Station',
      address: 'Race View Colony, Guindy, Chennai, Tamil Nadu 600032',
      latitude: 13.0067,
      longitude: 80.2025,
      category: 'Metro Station',
      categoryType: 'subway',
    ),
    GeocodedPlace(
      name: 'Chennai Beach (MSB)',
      address: 'Rajaji Salai, George Town, Chennai, Tamil Nadu 600001',
      latitude: 13.0910,
      longitude: 80.2925,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Coimbatore Junction (CBE)',
      address: 'Gopalapuram, Coimbatore, Tamil Nadu 641018',
      latitude: 11.0016,
      longitude: 76.9664,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Madurai Junction (MDU)',
      address: 'Railway Colony, Madurai, Tamil Nadu 625001',
      latitude: 9.9196,
      longitude: 78.1114,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Tiruchirappalli Junction (TPJ)',
      address: 'Sangillyandapuram, Tiruchirappalli, Tamil Nadu 620001',
      latitude: 10.7944,
      longitude: 78.6854,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Karnataka / Bengaluru
    GeocodedPlace(
      name: 'KSR Bengaluru City (SBC)',
      address: 'Kempegowda, Sevashrama, Bengaluru, Karnataka 560023',
      latitude: 12.9781,
      longitude: 77.5694,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Yesvantpur Junction (YPR)',
      address: 'Yeshwanthpur, Bengaluru, Karnataka 560022',
      latitude: 13.0238,
      longitude: 77.5502,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'SMVT Bengaluru (SMVB)',
      address: 'Baiyappanahalli, Bengaluru, Karnataka 560038',
      latitude: 13.0055,
      longitude: 77.6533,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Nadaprabhu Kempegowda Majestic Metro',
      address: 'Gubbi Thotadappa Rd, Majestic, Bengaluru, Karnataka 560023',
      latitude: 12.9756,
      longitude: 77.5728,
      category: 'Metro Station',
      categoryType: 'subway',
    ),
    GeocodedPlace(
      name: 'Mysuru Junction (MYS)',
      address: 'Medar Block, Yadavagiri, Mysuru, Karnataka 570001',
      latitude: 12.3164,
      longitude: 76.6444,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Maharashtra / Mumbai
    GeocodedPlace(
      name: 'Chhatrapati Shivaji Maharaj Terminus (CSMT)',
      address: 'Fort, Mumbai, Maharashtra 400001',
      latitude: 18.9401,
      longitude: 72.8354,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Dadar Central (DR)',
      address: 'Dadar West, Mumbai, Maharashtra 400028',
      latitude: 19.0183,
      longitude: 72.8432,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Mumbai Central (MMCT)',
      address: 'Nathani Heights, Mumbai Central, Mumbai, Maharashtra 400008',
      latitude: 18.9696,
      longitude: 72.8193,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Bandra Terminus (BDTS)',
      address: 'Bandra East, Mumbai, Maharashtra 400051',
      latitude: 19.0620,
      longitude: 72.8427,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Pune Junction (PUNE)',
      address: 'Agarkar Nagar, Pune, Maharashtra 411001',
      latitude: 18.5284,
      longitude: 73.8743,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Delhi NCR
    GeocodedPlace(
      name: 'New Delhi Railway Station (NDLS)',
      address: 'Bhavbhuti Marg, Ratan Lal Market, New Delhi, Delhi 110006',
      latitude: 28.6429,
      longitude: 77.2195,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Old Delhi Railway Station (DLI)',
      address: 'Chandni Chowk, New Delhi, Delhi 110006',
      latitude: 28.6619,
      longitude: 77.2280,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Hazrat Nizamuddin (NZM)',
      address: 'Nizamuddin, New Delhi, Delhi 110013',
      latitude: 28.5885,
      longitude: 77.2534,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Anand Vihar Terminal (ANVT)',
      address: 'Anand Vihar, New Delhi, Delhi 110092',
      latitude: 28.6508,
      longitude: 77.3152,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Rajiv Chowk Metro Station',
      address: 'Connaught Place, New Delhi, Delhi 110001',
      latitude: 28.6328,
      longitude: 77.2195,
      category: 'Metro Station',
      categoryType: 'subway',
    ),

    // West Bengal / Kolkata
    GeocodedPlace(
      name: 'Howrah Junction (HWH)',
      address: 'Station Road, Howrah, West Bengal 711101',
      latitude: 22.5839,
      longitude: 88.3426,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Sealdah (SDAH)',
      address: 'Bipin Behari Ganguly St, Sealdah, Kolkata, West Bengal 700014',
      latitude: 22.5678,
      longitude: 88.3712,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Telangana & Andhra Pradesh
    GeocodedPlace(
      name: 'Secunderabad Junction (SC)',
      address: 'Station Rd, Secunderabad, Telangana 500003',
      latitude: 17.4344,
      longitude: 78.5012,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Hyderabad Deccan Nampally (HYB)',
      address: 'Nampally, Hyderabad, Telangana 500001',
      latitude: 17.3924,
      longitude: 78.4697,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Vijayawada Junction (BZA)',
      address: 'Tarapet, Vijayawada, Andhra Pradesh 520001',
      latitude: 16.5186,
      longitude: 80.6201,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Kerala
    GeocodedPlace(
      name: 'Thiruvananthapuram Central (TVC)',
      address: 'Chalai Bazar, Thiruvananthapuram, Kerala 695014',
      latitude: 8.4875,
      longitude: 76.9532,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Ernakulam Junction South (ERS)',
      address: 'South Railway Station Rd, Ernakulam, Kochi, Kerala 682016',
      latitude: 9.9678,
      longitude: 76.2891,
      category: 'Railway Station',
      categoryType: 'station',
    ),

    // Gujarat & Rajasthan
    GeocodedPlace(
      name: 'Ahmedabad Junction (ADI)',
      address: 'Kalupur, Ahmedabad, Gujarat 380002',
      latitude: 23.0238,
      longitude: 72.6015,
      category: 'Railway Station',
      categoryType: 'station',
    ),
    GeocodedPlace(
      name: 'Jaipur Junction (JP)',
      address: 'Hasanpura, Jaipur, Rajasthan 302006',
      latitude: 26.9196,
      longitude: 75.7878,
      category: 'Railway Station',
      categoryType: 'station',
    ),
  ];

  static const _calculator = HaversineDistanceCalculator();

  /// Searches curated stations using case-insensitive query matching.
  static List<GeocodedPlace> search(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final matches = stations.where((s) {
      final n = s.name.toLowerCase();
      final a = s.address.toLowerCase();
      return n.contains(clean) || a.contains(clean);
    }).toList();

    return matches;
  }

  /// Finds the nearest station within [maxDistanceMeters] (default 800m).
  static GeocodedPlace? findNearest(
    double lat,
    double lon, {
    double maxDistanceMeters = 800.0,
  }) {
    GeocodedPlace? best;
    double bestDist = double.infinity;

    for (final s in stations) {
      final d = _calculator.distanceMeters(
        lat1: lat,
        lon1: lon,
        lat2: s.latitude,
        lon2: s.longitude,
      );
      if (d <= maxDistanceMeters && d < bestDist) {
        bestDist = d;
        best = s;
      }
    }

    return best;
  }
}
