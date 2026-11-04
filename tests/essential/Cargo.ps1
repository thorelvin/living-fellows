# SPDX-License-Identifier: MIT
# Ordered production sources and compact outcomes; each group gets a fresh Lua environment.
@{ Name = 'packing-and-camp-preparation'; Files = @(Get-ScGameplayFiles) + @(
    (Join-Path $Gameplay 'loadout_harness.lua')) }

@{ Name = 'home-reviewed-crew-journey'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Client 'SCExpeditionIntegration.lua'),
    (Join-Path $Client 'SCHomeTrip.lua'),
    (Join-Path $Client 'SCExpeditionPrototype.lua'),
    (Join-Path $Gameplay 'home_trip_fixture.lua'),
    (Join-Path $Essential 'home_journey_harness.lua')) }

@{ Name = 'wood-tools-and-collection'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCSpeechColors.lua'),
    (Join-Path $Client 'SCLoggingWork.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Core 'wood_collection_fixture.lua'),
    (Join-Path $Essential 'wood_collection_harness.lua')) }

@{ Name = 'cargo-return-storage-retry'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Core 'expedition_integration_fixture.lua'),
    (Join-Path $Client 'SCLoggingWork.lua'),
    (Join-Path $Client 'SCExpeditionWood.lua'),
    (Join-Path $Client 'SCExpeditionIntegration.lua'),
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
