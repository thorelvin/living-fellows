-- SPDX-License-Identifier: MIT
-- The base-work module derives its native build action while loading; this
-- focused patrol group never constructs or executes a build action.
ISBuildAction = ISBaseTimedAction:derive("ISBuildAction")
