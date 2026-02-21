from flask import Blueprint, abort, redirect, render_template, request, url_for

from .models import (
    create_link,
    delete_link,
    get_all_links,
    get_link,
    get_stats,
    record_hit,
    update_link,
)
from .validation import validate_link

bp = Blueprint("main", __name__)


@bp.route("/")
def home():
    links = get_all_links()
    stats = get_stats()
    return render_template("home.html", links=links, stats=stats)


@bp.route("/healthz")
def healthz():
    return "ok"


@bp.route("/help")
def help_page():
    return render_template("help.html")


# --- CRUD ---


@bp.route("/links", methods=["POST"])
def create():
    slug = request.form.get("slug", "").strip().lower()
    url = request.form.get("url", "").strip()
    description = request.form.get("description", "").strip()

    errors = validate_link(slug, url)
    if not errors and get_link(slug):
        errors.append(f"Alias '{slug}' already exists.")

    if errors:
        links = get_all_links()
        stats = get_stats()
        return (
            render_template(
                "home.html",
                links=links,
                stats=stats,
                errors=errors,
                form={"slug": slug, "url": url, "description": description},
            ),
            400,
        )

    create_link(slug, url, description)
    return redirect(url_for("main.home"))


@bp.route("/links/<slug>", methods=["POST"])
def update(slug):
    method = request.form.get("_method", "").upper()

    if method == "DELETE":
        delete_link(slug)
        return redirect(url_for("main.home"))

    if method == "PUT":
        url = request.form.get("url", "").strip()
        description = request.form.get("description", "").strip()
        errors = validate_link(slug, url)
        if errors:
            links = get_all_links()
            stats = get_stats()
            return (
                render_template("home.html", links=links, stats=stats, errors=errors),
                400,
            )
        update_link(slug, url, description)
        return redirect(url_for("main.home"))

    abort(405)


# --- Redirect (catch-all, must be last) ---


@bp.route("/<slug>")
def redirect_slug(slug):
    link = get_link(slug)
    if not link:
        return render_template("404.html", slug=slug), 404
    record_hit(slug)
    return redirect(link["url"], code=302)
