import { LightningElement, wire } from 'lwc';
import getCycleOptions from '@salesforce/apex/BusinessSegmentPerformanceController.getCycleOptions';
import getBusinessSegmentOptions from '@salesforce/apex/BusinessSegmentPerformanceController.getBusinessSegmentOptions';
import getSegmentPerformance from '@salesforce/apex/BusinessSegmentPerformanceController.getSegmentPerformance';
import getCyclePerformance from '@salesforce/apex/BusinessSegmentPerformanceController.getCyclePerformance';
import getCompanySizePerformance from '@salesforce/apex/BusinessSegmentPerformanceController.getCompanySizePerformance';

const GROUP_BY_OPTIONS = [
    { label: 'Business Segment', value: 'segment' },
    { label: 'Company Size', value: 'size' }
];

const SIZE_TIER_TYPE_OPTIONS = [
    { label: 'By Employees', value: 'employees' },
    { label: 'By Revenue', value: 'revenue' }
];

const DEFAULT_RANGE_DAYS = 30;

const BAR_WIDTH = 28;
const BAR_WIDTH_MAX = 80;
const BAR_GAP = 12;
const BAR_CHART_HEIGHT = 220;
const BAR_CHART_TOP_PADDING = 24;
const BAR_CHART_BASELINE_PADDING = 56;
const BAR_CHART_MIN_WIDTH = 600;
const BAR_CHART_DEFAULT_LIMIT = 20;

const BAR_METRIC_OPTIONS = [
    { label: 'Email Sent', value: 'emailSent' },
    { label: 'Email Open Rate', value: 'emailOpenRate' },
    { label: 'Email Click Rate', value: 'emailClickRate' },
    { label: 'LinkedIn Sent', value: 'linkedInSent' },
    { label: 'LinkedIn Connect Rate', value: 'linkedInConnectRate' },
    { label: 'Calls Made', value: 'callsMade' },
    { label: 'Call Connect Rate', value: 'callConnectRate' }
];

export default class BusinessSegmentPerformance extends LightningElement {
    allSegments = [];
    cycleOptionsList = [];
    selectedCycle;
    selectedSegmentId;
    segmentSearchTerm = '';
    startDate;
    endDate;
    isLoadingOptions = true;
    isLoadingSegment = false;
    isLoadingCycle = false;
    error;
    segmentPerformance;

    isAllSegmentsView = false;
    cycleSegmentPerformances = [];
    selectedBarMetric = 'emailOpenRate';
    barSearchTerm = '';
    showAllBars = false;
    chartContainerWidth = BAR_CHART_MIN_WIDTH;
    _resizeObserver;

    groupByMode = 'segment';
    sizeTierType = 'employees';

    connectedCallback() {
        const today = new Date();
        const past = new Date();
        past.setDate(today.getDate() - DEFAULT_RANGE_DAYS);
        this.endDate = this.toIsoDate(today);
        this.startDate = this.toIsoDate(past);
    }

    renderedCallback() {
        if (this._resizeObserver) {
            return;
        }
        const el = this.template.querySelector('.bar-chart-scroll');
        if (!el) {
            return;
        }
        this._resizeObserver = new ResizeObserver((entries) => {
            const width = entries[0].contentRect.width;
            if (width && Math.abs(width - this.chartContainerWidth) > 1) {
                this.chartContainerWidth = width;
            }
        });
        this._resizeObserver.observe(el);
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = undefined;
        }
    }

    toIsoDate(d) {
        return d.toISOString().slice(0, 10);
    }

    @wire(getCycleOptions)
    wiredCycleOptions({ data, error }) {
        if (data) {
            this.cycleOptionsList = data.map((c) => ({ label: c, value: c }));
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    @wire(getBusinessSegmentOptions)
    wiredSegmentOptions({ data, error }) {
        this.isLoadingOptions = false;
        if (data) {
            this.allSegments = data;
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    get groupByOptions() {
        return GROUP_BY_OPTIONS;
    }

    get sizeTierTypeOptions() {
        return SIZE_TIER_TYPE_OPTIONS;
    }

    get isSizeMode() {
        return this.groupByMode === 'size';
    }

    get barGroupLabel() {
        return this.isSizeMode ? 'Company Size' : 'Business Type';
    }

    get barFilterLabel() {
        return this.isSizeMode ? 'Filter size tiers' : 'Filter business types';
    }

    get barFilterPlaceholder() {
        return this.isSizeMode ? 'Search tier names...' : 'Search business type names...';
    }

    get barNoMatchMessage() {
        return this.isSizeMode
            ? `No size tiers match "${this.barSearchTerm}".`
            : `No business types in this cycle match "${this.barSearchTerm}".`;
    }

    get barNoActivityMessage() {
        return this.isSizeMode
            ? 'No outreach activity in this date range.'
            : 'No activity in this date range for this cycle.';
    }

    get chartHeading() {
        if (this.isSizeMode) {
            const found = SIZE_TIER_TYPE_OPTIONS.find((o) => o.value === this.sizeTierType);
            return `Company Size — ${found ? found.label.replace('By ', '') : ''}`;
        }
        return `All Business Types — ${this.selectedCycle}`;
    }

    get accountCountLabel() {
        return this.isSizeMode
            ? `${this.accountCount} account(s) with outreach activity in this tier`
            : `${this.accountCount} account(s) assigned to this business type`;
    }

    get hasCycleSelected() {
        return !!this.selectedCycle;
    }

    get isCycleNotSelected() {
        return !this.selectedCycle;
    }

    get hasSegmentSelected() {
        return !!this.selectedSegmentId;
    }

    get hasAnyViewSelected() {
        return this.hasSegmentSelected || this.isAllSegmentsView;
    }

    get isBusy() {
        return this.isLoadingSegment || this.isLoadingCycle;
    }

    get segmentListForCycle() {
        if (!this.selectedCycle) {
            return [];
        }
        const term = this.segmentSearchTerm.toLowerCase();
        return this.allSegments
            .filter((s) => s.cycle === this.selectedCycle)
            .filter((s) => !term || s.business.toLowerCase().includes(term))
            .map((s) => ({
                ...s,
                itemClass:
                    !this.isAllSegmentsView && s.segmentId === this.selectedSegmentId
                        ? 'segment-item segment-item_selected'
                        : 'segment-item'
            }));
    }

    get allSegmentsItemClass() {
        return this.isAllSegmentsView
            ? 'segment-item segment-item_all segment-item_selected'
            : 'segment-item segment-item_all';
    }

    get selectedSegmentName() {
        if (this.isSizeMode) {
            const match = this.cycleSegmentPerformances.find((s) => s.segmentId === this.selectedSegmentId);
            return match ? match.business : '';
        }
        const match = this.allSegments.find((s) => s.segmentId === this.selectedSegmentId);
        return match ? match.business : '';
    }

    handleCycleChange(event) {
        this.selectedCycle = event.detail.value;
        this.selectedSegmentId = undefined;
        this.segmentSearchTerm = '';
        this.segmentPerformance = undefined;
        this.isAllSegmentsView = false;
        this.cycleSegmentPerformances = [];
        this.barSearchTerm = '';
        this.showAllBars = false;
    }

    handleSegmentSearch(event) {
        this.segmentSearchTerm = event.target.value;
    }

    handleSegmentSelect(event) {
        this.selectedSegmentId = event.currentTarget.dataset.id;
        this.isAllSegmentsView = false;
        this.loadSegmentPerformance();
    }

    handleShowAllSegments() {
        this.isAllSegmentsView = true;
        this.selectedSegmentId = undefined;
        this.segmentPerformance = undefined;
        this.barSearchTerm = '';
        this.showAllBars = false;
        this.loadCyclePerformance();
    }

    handleBarClick(event) {
        this.selectedSegmentId = event.currentTarget.dataset.id;
        this.isAllSegmentsView = false;
        if (this.isSizeMode) {
            // All tiers' full metrics were already returned by the one getCompanySizePerformance
            // call - no need for a second round-trip to drill into a single tier.
            const match = this.cycleSegmentPerformances.find((s) => s.segmentId === this.selectedSegmentId);
            this.segmentPerformance = match || null;
        } else {
            this.loadSegmentPerformance();
        }
    }

    handleBackToAllTiers() {
        this.selectedSegmentId = undefined;
        this.segmentPerformance = undefined;
        this.isAllSegmentsView = true;
    }

    handleGroupByChange(event) {
        this.groupByMode = event.detail.value;
        this.selectedSegmentId = undefined;
        this.segmentPerformance = undefined;
        this.isAllSegmentsView = false;
        this.cycleSegmentPerformances = [];
        this.barSearchTerm = '';
        this.showAllBars = false;
        this.selectedCycle = undefined;
        this.segmentSearchTerm = '';
        if (this.isSizeMode) {
            this.isAllSegmentsView = true;
            this.loadCompanySizePerformance();
        }
    }

    handleSizeTierTypeChange(event) {
        this.sizeTierType = event.detail.value;
        this.selectedSegmentId = undefined;
        this.segmentPerformance = undefined;
        this.isAllSegmentsView = true;
        this.loadCompanySizePerformance();
    }

    handleBarMetricChange(event) {
        this.selectedBarMetric = event.detail.value;
    }

    handleBarSearch(event) {
        this.barSearchTerm = event.target.value;
    }

    handleToggleShowAllBars() {
        this.showAllBars = !this.showAllBars;
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
        this.refreshActiveView();
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
        this.refreshActiveView();
    }

    refreshActiveView() {
        if (this.isSizeMode) {
            this.loadCompanySizePerformance();
        } else if (this.isAllSegmentsView) {
            this.loadCyclePerformance();
        } else {
            this.loadSegmentPerformance();
        }
    }

    loadCompanySizePerformance() {
        if (!this.startDate || !this.endDate) {
            return;
        }
        this.isLoadingCycle = true;
        this.error = undefined;
        getCompanySizePerformance({
            tierType: this.sizeTierType,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => {
                this.cycleSegmentPerformances = result.map((tp) => ({
                    segmentId: tp.tierKey,
                    business: tp.label,
                    accountCount: tp.accountCount,
                    metrics: tp.metrics
                }));
                if (this.selectedSegmentId) {
                    const match = this.cycleSegmentPerformances.find(
                        (s) => s.segmentId === this.selectedSegmentId
                    );
                    this.segmentPerformance = match || null;
                }
            })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.cycleSegmentPerformances = [];
            })
            .finally(() => {
                this.isLoadingCycle = false;
            });
    }

    loadSegmentPerformance() {
        if (!this.selectedSegmentId || !this.startDate || !this.endDate) {
            return;
        }
        this.isLoadingSegment = true;
        this.error = undefined;
        getSegmentPerformance({
            segmentId: this.selectedSegmentId,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => {
                this.segmentPerformance = result;
            })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.segmentPerformance = undefined;
            })
            .finally(() => {
                this.isLoadingSegment = false;
            });
    }

    loadCyclePerformance() {
        if (!this.selectedCycle || !this.startDate || !this.endDate) {
            return;
        }
        this.isLoadingCycle = true;
        this.error = undefined;
        getCyclePerformance({
            cycle: this.selectedCycle,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => {
                this.cycleSegmentPerformances = result;
            })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.cycleSegmentPerformances = [];
            })
            .finally(() => {
                this.isLoadingCycle = false;
            });
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }

    get metrics() {
        return this.segmentPerformance ? this.segmentPerformance.metrics : null;
    }

    get accountCount() {
        return this.segmentPerformance ? this.segmentPerformance.accountCount : 0;
    }

    get barMetricOptions() {
        return BAR_METRIC_OPTIONS;
    }

    get barMetricLabel() {
        const found = BAR_METRIC_OPTIONS.find((o) => o.value === this.selectedBarMetric);
        return found ? found.label : '';
    }

    get isRateMetric() {
        return this.selectedBarMetric.toLowerCase().includes('rate');
    }

    get filteredCycleSegments() {
        const term = this.barSearchTerm.toLowerCase().trim();
        if (!term) {
            return this.cycleSegmentPerformances;
        }
        return this.cycleSegmentPerformances.filter((s) => s.business.toLowerCase().includes(term));
    }

    get hasCycleSegmentPerformances() {
        return this.cycleSegmentPerformances.length > 0;
    }

    get hasFilteredCycleSegments() {
        return this.filteredCycleSegments.length > 0;
    }

    get isBarListTruncated() {
        return (
            !this.showAllBars &&
            !this.barSearchTerm.trim() &&
            this.filteredCycleSegments.length > BAR_CHART_DEFAULT_LIMIT
        );
    }

    get showAllBarsLabel() {
        return this.showAllBars
            ? 'Show top 20 only'
            : `Show all ${this.filteredCycleSegments.length} segments`;
    }

    get showToggleAllBarsButton() {
        return (
            !this.barSearchTerm.trim() && this.filteredCycleSegments.length > BAR_CHART_DEFAULT_LIMIT
        );
    }

    get barCountLabel() {
        const total = this.filteredCycleSegments.length;
        const shown = this.cycleBars.length;
        if (shown === total) {
            return `Showing all ${total} segment${total === 1 ? '' : 's'}`;
        }
        return `Showing top ${shown} of ${total} segments`;
    }

    get cycleChartHeight() {
        return BAR_CHART_HEIGHT;
    }

    computeBarWidth(count) {
        if (!count) {
            return BAR_WIDTH;
        }
        const available = this.chartContainerWidth - BAR_GAP * (count + 1);
        const natural = available / count;
        return Math.min(Math.max(natural, BAR_WIDTH), BAR_WIDTH_MAX);
    }

    get cycleChartWidth() {
        const count = this.cycleBars.length;
        const barWidth = this.computeBarWidth(count);
        const width = BAR_GAP + count * (barWidth + BAR_GAP);
        return Math.max(width, BAR_CHART_MIN_WIDTH);
    }

    get cycleBars() {
        const summaries = this.filteredCycleSegments;
        if (!summaries.length) {
            return [];
        }
        const metric = this.selectedBarMetric;
        const isRate = this.isRateMetric;
        const sorted = [...summaries].sort(
            (a, b) => (b.metrics[metric] || 0) - (a.metrics[metric] || 0)
        );
        const visible = this.isBarListTruncated ? sorted.slice(0, BAR_CHART_DEFAULT_LIMIT) : sorted;

        const barWidth = this.computeBarWidth(visible.length);
        const baselineY = BAR_CHART_HEIGHT - BAR_CHART_BASELINE_PADDING;
        const availableHeight = baselineY - BAR_CHART_TOP_PADDING;
        const maxValue = Math.max(...visible.map((s) => s.metrics[metric] || 0), 0);

        return visible.map((s, index) => {
            const value = s.metrics[metric] || 0;
            const rawHeight = maxValue > 0 ? (value / maxValue) * availableHeight : 0;
            const height = value > 0 ? Math.max(rawHeight, 2) : 0;
            const x = BAR_GAP + index * (barWidth + BAR_GAP);
            const nameX = x + barWidth / 2;
            const nameY = baselineY + 14;
            const shortName = s.business.length > 16 ? `${s.business.slice(0, 15)}…` : s.business;
            return {
                key: s.segmentId,
                segmentId: s.segmentId,
                business: s.business,
                shortName,
                value,
                displayValue: isRate ? `${value}%` : String(value),
                x,
                y: baselineY - height,
                width: barWidth,
                height,
                labelY: Math.max(baselineY - height - 6, 10),
                nameX,
                nameY,
                nameTransform: `rotate(-40 ${nameX} ${nameY})`
            };
        });
    }
}
