# SPDX-License-Identifier: MIT
# Ordered production sources and compact outcomes; each group gets a fresh Lua environment.
@{ Name = 'fuel-inlet-and-camp-refuel-recovery'; Files = @(
    (Join-Path $Core 'vehicle_refuel_fixture.lua'),
    (Join-Path $Client 'SCBaseFuel.lua'),
    (Join-Path $Client 'SCVehicleRefuel.lua'),
    (Join-Path $Core 'vehicle_refuel_harness.lua')) }

@{ Name = 'fuel-native-transfers-generator-and-delivery'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISTakeFuel.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISAddFuel.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISActivateGenerator.lua'),
    (Join-Path $GameRoot 'media\lua\shared\TimedActions\ISPlugGenerator.lua'),
    (Join-Path $GameRoot 'media\lua\shared\Vehicles\TimedActions\ISAddGasolineToVehicle.lua'),
    (Join-Path $GameRoot 'media\lua\shared\Fluids\ISFluidTransferAction.lua'),
    (Join-Path $Client 'SCNativeTraversalActions.lua'),
    (Join-Path $Client 'SCNativeVisualActions.lua'),
    (Join-Path $Client 'SCNativeCombatActions.lua'),
    (Join-Path $Client 'SCNativeWorkActions.lua'),
    (Join-Path $Client 'SCNativeMovementActions.lua'),
    (Join-Path $Client 'SCNativeActions.lua'),
    (Join-Path $Client 'SCFuelStations.lua'),
    (Join-Path $Client 'SCExpeditionFuel.lua'),
    (Join-Path $Essential 'fuel_expedition_harness.lua')) }

@{ Name = 'log-yard-native-stacking'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Client 'SCNativeTraversalActions.lua'),
    (Join-Path $Client 'SCNativeVisualActions.lua'),
    (Join-Path $Client 'SCNativeCombatActions.lua'),
    (Join-Path $Client 'SCNativeWorkActions.lua'),
    (Join-Path $Client 'SCNativeMovementActions.lua'),
    (Join-Path $Client 'SCNativeActions.lua'),
    (Join-Path $GameRoot 'media\lua\shared\Entity\TimedActions\ISHandcraftAction.lua'),
    (Join-Path $Client 'SCLogYard.lua'),
    (Join-Path $Essential 'log_yard_harness.lua')) }

@{ Name = 'packing-and-camp-preparation'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'loadout_harness.lua'),
    (Join-Path $Essential 'sorting_scan_harness.lua')) }

@{ Name = 'loot-batches-ownership-and-nested-sources'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'loot_haul_harness.lua')) }

@{ Name = 'home-reviewed-crew-journey'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Client 'SCExpeditionIntegration.lua'),
    (Join-Path $Client 'SCHomeTrip.lua'),
    (Join-Path $Shared 'SCForceEntryState.lua'),
    (Join-Path $Client 'SCForceEntry.lua'),
    (Join-Path $Client 'SCExpeditionPrototype.lua'),
    (Join-Path $Gameplay 'home_trip_fixture.lua'),
    (Join-Path $Essential 'home_journey_harness.lua')) }

@{ Name = 'expedition-car-preflight-and-parking'; Files = @(
    (Join-Path $Core 'expedition_car_fixture.lua'),
    (Join-Path $Client 'SCExpeditionCar.lua'),
    (Join-Path $Core 'expedition_car_harness.lua')) }

@{ Name = 'driving-ownership-and-obstacle-replanning'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCStableValue.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $Core 'driving_fixture.lua'),
    (Join-Path $Client 'SCActionSupervisor.lua'),
    (Join-Path $Client 'SCScheduler.lua'),
    (Join-Path $Client 'SCExpeditionRoute.lua'),
    (Join-Path $Client 'SCDriving.lua'),
    (Join-Path $Client 'SCConvoy.lua'),
    (Join-Path $Client 'SCGuardPost.lua'),
    (Join-Path $Client 'SCCommands.lua'),
    (Join-Path $Client 'SCDecision.lua'),
    (Join-Path $Client 'SCRuntime.lua'),
    (Join-Path $Core 'driving_harness.lua')) }

@{ Name = 'wood-tools-and-collection'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Client 'SCLoggingWork.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Client 'SCExpeditionTargets.lua'),
    (Join-Path $Core 'wood_collection_fixture.lua'),
    (Join-Path $Essential 'wood_collection_harness.lua')) }

@{ Name = 'forest-discovery-and-loaded-timber'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCExpeditionForests.lua'),
    (Join-Path $Core 'expedition_forests_harness.lua')) }

@{ Name = 'wood-controller-ownership'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCPersonalItems.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Client 'SCDecision.lua'),
    (Join-Path $Core 'wood_decision_harness.lua')) }

@{ Name = 'logging-area-progress-and-reload'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Client 'SCExpeditionRoute.lua'),
    (Join-Path $Client 'SCExpeditionForests.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Client 'SCExpeditionTargets.lua'),
    (Join-Path $Client 'SCExpeditionFuel.lua'),
    (Join-Path $Shared 'SCForceEntryState.lua'),
    (Join-Path $Client 'SCForceEntry.lua'),
    (Join-Path $Client 'SCExpeditionPrototype.lua'),
    (Join-Path $Core 'expedition_wood_mission_harness.lua')) }

@{ Name = 'cargo-return-storage-retry'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Core 'expedition_integration_fixture.lua'),
    (Join-Path $Client 'SCLoggingWork.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Client 'SCExpeditionIntegration.lua'),
    (Join-Path $Shared 'SCForceEntryState.lua'),
    (Join-Path $Client 'SCForceEntry.lua'),
    (Join-Path $Client 'SCExpeditionPrototype.lua'),
    (Join-Path $Core 'wood_expedition_integration_fixture.lua'),
    (Join-Path $Essential 'cargo_delivery_harness.lua')) }

@{ Name = 'taxi-identity-pending-payment'; Files = @(
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCTaxiBooking.lua'),
    (Join-Path $Client 'SCTaxiCab.lua'),
    (Join-Path $Client 'SCTaxiFares.lua'),
    (Join-Path $Core 'taxi_fare_recovery_fixture.lua'),
    (Join-Path $Essential 'taxi_recovery_harness.lua')) }
