"""Sync orchestration. Pull plans down, push results up.

Outermost layer (peer of api); depends on db, models, config.
Must not depend on api routes directly — shared logic belongs in a service module.
"""
