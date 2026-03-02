from dataclasses import dataclass

from django.db.models import Q, QuerySet


@dataclass(frozen=True)
class RecordFilterParams:
    inventory_name: str = 'default'
    warehouse_filter: str = ''
    category_filter: str = ''
    exact_date: str = ''
    date_from: str = ''
    date_to: str = ''
    search_filter: str = ''


@dataclass(frozen=True)
class SliceParams:
    limit: int
    offset: int


def clamp_int(value: str | None, default: int, min_value: int, max_value: int) -> int:
    try:
        parsed = int(value) if value is not None else default
    except (TypeError, ValueError):
        parsed = default
    return max(min_value, min(parsed, max_value))


def slice_from_request(
    request,
    *,
    default_limit: int,
    max_limit: int,
    default_offset: int = 0,
    max_offset: int = 100000,
) -> SliceParams:
    limit = clamp_int(request.GET.get('limit'), default_limit, 1, max_limit)
    offset = clamp_int(request.GET.get('offset'), default_offset, 0, max_offset)
    return SliceParams(limit=limit, offset=offset)


def record_filters_from_request(request, inventory_name: str = 'default') -> RecordFilterParams:
    return RecordFilterParams(
        inventory_name=request.GET.get('inventory_name', inventory_name),
        warehouse_filter=request.GET.get('warehouse', ''),
        category_filter=request.GET.get('category', ''),
        exact_date=request.GET.get('date', ''),
        date_from=request.GET.get('date_from', ''),
        date_to=request.GET.get('date_to', ''),
        search_filter=request.GET.get('search', ''),
    )


def apply_record_filters(queryset: QuerySet, filters: RecordFilterParams) -> QuerySet:
    filtered = queryset.filter(product__inventory_name=filters.inventory_name)

    if filters.warehouse_filter:
        filtered = filtered.filter(warehouse__icontains=filters.warehouse_filter)
    if filters.category_filter:
        filtered = filtered.filter(category__icontains=filters.category_filter)

    if filters.exact_date:
        filtered = filtered.filter(date=filters.exact_date)
    else:
        if filters.date_from:
            filtered = filtered.filter(date__gte=filters.date_from)
        if filters.date_to:
            filtered = filtered.filter(date__lte=filters.date_to)

    if filters.search_filter:
        filtered = filtered.filter(
            Q(product__code__icontains=filters.search_filter)
            | Q(product__description__icontains=filters.search_filter)
        )

    return filtered
