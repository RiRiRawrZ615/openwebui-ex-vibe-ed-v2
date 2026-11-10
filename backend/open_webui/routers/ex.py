"""Open Web Vibes clean router: settings and theme only.

This is the entire EX backend in the clean fork. Settings live in the normal user
settings record (ui.ex), the theme engine is the pure visual module, and nothing
here knows about loop guard, context windows, compression, or any single machine.

Context management is not an Open WebUI feature in this design. It belongs to the
billion-context proxy sitting between Open WebUI and the engine, so the request
path stays exactly upstream.

Wiring in main.py:

    from open_webui import ex
    app.include_router(ex.router, prefix="/api/v1/ex")
"""

import logging
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from open_webui.env import DATA_DIR
from open_webui.models.users import Users
from open_webui.utils.auth import get_current_user
from open_webui.utils import ex_theme
from open_webui.utils.ex_settings import resolve_ex_settings

log = logging.getLogger(__name__)

router = APIRouter()


def _theme_roots() -> list[Path]:
    """Wallpaper/icon roots. Only the data dir by default; extend with
    EX_THEME_ROOTS (colon separated) on machines that keep art elsewhere.
    """
    extra = [p for p in str(getattr(__import__("os"), "environ", {}).get("EX_THEME_ROOTS", "")).split(":") if p]
    return [Path(DATA_DIR)] + [Path(p) for p in extra]


@router.get("/settings")
async def ex_settings_read(user=Depends(get_current_user)):
    return {"settings": resolve_ex_settings(user)}


@router.post("/settings")
async def ex_settings_write(patch: dict[str, Any], user=Depends(get_current_user)):
    current = resolve_ex_settings(user)
    unknown = [key for key in patch if key not in current]
    if unknown:
        raise HTTPException(status_code=400, detail=f"unknown setting key: {', '.join(unknown)}")

    merged = {**current, **patch}
    updated = await Users.update_user_settings_by_id(user.id, {"ui": {"ex": merged}})
    if updated is None:
        raise HTTPException(status_code=404, detail="user not found")
    return {"settings": merged, "user_id": user.id}


@router.get("/theme")
async def ex_theme_read(user=Depends(get_current_user)):
    settings = resolve_ex_settings(user)
    theme = ex_theme.build_theme(
        settings.get("themeName", "navy"),
        settings.get("themeAccent", ""),
        settings.get("themeSurface", ""),
        settings.get("themeText", ""),
        gradient_stops=list(settings.get("themeGradient") or []),
        wallpaper_value=settings.get("themeWallpaper", ""),
        icon_path=settings.get("themeIcon", ""),
        roots=_theme_roots(),
        adjust_by=settings.get("themeAdjust", 0),
    )
    return {"theme": theme, "css": ex_theme.css_tokens(theme)}
