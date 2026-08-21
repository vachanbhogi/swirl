"""Swirl Jac full-stack entry point."""

import "./frontend/src/index.css";
import from .frontend.client.App { SwirlApp }
import from .frontend.client.NotchOverlay { NotchOverlay }


def:pub app -> JsxElement {
    location: any = window.location;  # jac:ignore[W2001]
    if location.hash == "#/notch" or location.pathname == "/notch" {
        return <NotchOverlay />;
    }
    return <SwirlApp />;
}
