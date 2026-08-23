import 'package:gamma_app/data/device_inventory.dart';

/// Fake compartido de F3-C Fases 6/7 (Areas): CRUD de áreas grabado, errores
/// inyectables y snapshot de dispositivos instantáneo para los subtítulos de
/// conteo. Instant returns: los tests de widget bombean el estado sin
/// `pumpAndSettle` sobre timers reales.
class AreasFakeRepo implements DeviceInventoryRepository {
  AreasFakeRepo({List<HomeArea>? areas, List<PhysicalDevice>? devices})
    : areas = List.of(areas ?? const []),
      devices = List.of(devices ?? const []);

  List<HomeArea> areas;
  List<PhysicalDevice> devices;
  final created = <(String, List<String>)>[];
  final updated = <(String, String)>[];
  final updatedAliases = <List<String>>[];
  final deleted = <String>[];
  Object? deleteError;
  Object? updateError;
  Object? createError;

  @override
  bool get supportsIdentify => false;

  @override
  bool get supportsSemanticRole => false;

  @override
  Future<DeviceInventorySnapshot> load() async => _snapshot();

  @override
  Future<DeviceInventorySnapshot> discover() async => _snapshot();

  DeviceInventorySnapshot _snapshot() => DeviceInventorySnapshot(
    areas: List.unmodifiable(areas),
    devices: List.unmodifiable(devices),
    gateways: const [],
    lastDiscoveryLabel: '',
  );

  @override
  Future<List<HomeArea>> listAreas() async => List.unmodifiable(areas);

  @override
  Future<HomeArea> createArea(
    String name, {
    List<String> aliases = const [],
  }) async {
    if (createError != null) throw createError!;
    created.add((name, aliases));
    final area = HomeArea(
      id: 'area_N${created.length}',
      name: name,
      aliases: aliases,
    );
    areas = [...areas, area];
    return area;
  }

  @override
  Future<HomeArea> updateArea(
    String areaId, {
    String? name,
    List<String>? aliases,
  }) async {
    if (updateError != null) throw updateError!;
    updated.add((areaId, name ?? ''));
    if (aliases != null) updatedAliases.add(aliases);
    areas = [
      for (final area in areas)
        if (area.id == areaId)
          HomeArea(
            id: areaId,
            name: name ?? area.name,
            aliases: aliases ?? area.aliases,
          )
        else
          area,
    ];
    return areas.firstWhere((area) => area.id == areaId);
  }

  @override
  Future<void> deleteArea(String areaId) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(areaId);
    areas = [
      for (final area in areas)
        if (area.id != areaId) area,
    ];
  }

  @override
  Future<PhysicalDevice> assignPhysicalArea(String deviceId, String? areaId) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointArea(
    String deviceId,
    String endpointId,
    String? areaId,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> assignEndpointSemanticRole(
    String deviceId,
    String endpointId,
    String? role,
  ) => throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameDevice(String deviceId, String? userName) =>
      throw UnimplementedError();

  @override
  Future<PhysicalDevice> renameEndpoint(
    String deviceId,
    String endpointId,
    String? userName,
  ) => throw UnimplementedError();

  @override
  Future<void> identify(String deviceId, {String? endpointId}) async {}
}

/// Dispositivo asignado físicamente a `area_SALA` para verificar el conteo
/// por área en lista desktop y wall.
const salaDevice = PhysicalDevice(
  id: 'dev_sala_01',
  name: 'Luz sala',
  kind: DeviceKind.light,
  provider: 'Tuya',
  providerDeviceId: '',
  model: 'M',
  provisioningState: DeviceProvisioningState.configured,
  online: true,
  health: DeviceHealthState.online,
  physicalAreaId: 'area_SALA',
  endpoints: [],
);
