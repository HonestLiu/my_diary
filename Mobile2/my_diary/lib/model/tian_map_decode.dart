// ==== 天地图 Geocoder(逆地理编码查询) 数据模型 ====
class TdtGeocodeResponse {
  final TdtResult? result;
  final String msg;
  final String status; // "0" 表示成功
  TdtGeocodeResponse(
      {required this.result, required this.msg, required this.status});
  factory TdtGeocodeResponse.fromJson(Map<String, dynamic> json) =>
      TdtGeocodeResponse(
        result: json['result'] == null
            ? null
            : TdtResult.fromJson(json['result'] as Map<String, dynamic>),
        msg: json['msg']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
      );
  bool get isOk => status == '0';
}

class TdtResult {
  final String formattedAddress;
  final TdtLocation? location;
  final TdtAddressComponent? addressComponent;
  TdtResult(
      {required this.formattedAddress,
      required this.location,
      required this.addressComponent});
  factory TdtResult.fromJson(Map<String, dynamic> json) => TdtResult(
        formattedAddress: json['formatted_address']?.toString() ?? '',
        location: json['location'] == null
            ? null
            : TdtLocation.fromJson(json['location'] as Map<String, dynamic>),
        addressComponent: json['addressComponent'] == null
            ? null
            : TdtAddressComponent.fromJson(
                json['addressComponent'] as Map<String, dynamic>),
      );
}

class TdtLocation {
  final double lon;
  final double lat;
  TdtLocation({required this.lon, required this.lat});
  factory TdtLocation.fromJson(Map<String, dynamic> json) => TdtLocation(
        lon: (json['lon'] ?? 0).toDouble(),
        lat: (json['lat'] ?? 0).toDouble(),
      );
}

class TdtAddressComponent {
  final String address;
  final String town;
  final String nation;
  final String city;
  final String county;
  final String province;
  final String poi;
  final String road;
  final int? roadDistance;
  final int? addressDistance;
  final int? poiDistance;
  TdtAddressComponent({
    required this.address,
    required this.town,
    required this.nation,
    required this.city,
    required this.county,
    required this.province,
    required this.poi,
    required this.road,
    this.roadDistance,
    this.addressDistance,
    this.poiDistance,
  });
  factory TdtAddressComponent.fromJson(Map<String, dynamic> json) =>
      TdtAddressComponent(
        address: json['address']?.toString() ?? '',
        town: json['town']?.toString() ?? '',
        nation: json['nation']?.toString() ?? '',
        city: json['city']?.toString() ?? '',
        county: json['county']?.toString() ?? '',
        province: json['province']?.toString() ?? '',
        poi: json['poi']?.toString() ?? '',
        road: json['road']?.toString() ?? '',
        roadDistance: _toIntNullable(json['road_distance']),
        addressDistance: _toIntNullable(json['address_distance']),
        poiDistance: _toIntNullable(json['poi_distance']),
      );
}

int? _toIntNullable(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}
