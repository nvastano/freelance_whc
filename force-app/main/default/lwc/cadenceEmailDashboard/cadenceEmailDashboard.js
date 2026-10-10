import { LightningElement, wire } from 'lwc';
import getCadenceOptions from '@salesforce/apex/CadenceEmailDashboardController.getCadenceOptions';
import getDashboardData from '@salesforce/apex/CadenceEmailDashboardController.getDashboardData';
import getFolderCadenceMetrics from '@salesforce/apex/CadenceEmailDashboardController.getFolderCadenceMetrics';

const DEFAULT_RANGE_DAYS = 30;
const CHART_WIDTH = 600;
const CHART_HEIGHT = 160;
const CHART_PADDING = 12;

const BAR_WIDTH = 28;
const BAR_GAP = 12;
const BAR_CHART_HEIGHT = 220;
const BAR_CHART_TOP_PADDING = 24;
const BAR_CHART_BASELINE_PADDING = 56;
const BAR_CHART_MIN_WIDTH = 600;
const BAR_CHART_DEFAULT_LIMIT = 20;

const BAR_METRIC_OPTIONS = [
    { label: 'Sent', value: 'sent' },
    { label: 'Open Rate', value: 'openRate' },
    { label: 'Click Rate', value: 'clickRate' }
];

export default class CadenceEmailDashboard extends LightningElement {
    allCadences = [];
    folderOptions = [];
    selectedFolder;
    selectedCadenceId;
    cadenceSearchTerm = '';
    startDate;
    endDate;
    isLoadingOptions = true;
    isLoadingData = false;
    isLoadingFolderMetrics = false;
    error;
    dashboardData;

    isAllCadencesView = false;
    folderCadenceSummaries = [];
    selectedBarMetric = 'openRate';
    barSearchTerm = '';
    showAllBars = false;

    connectedCallback() {
        const today = new Date();
        const past = new Date();
        past.setDate(today.getDate() - DEFAULT_RANGE_DAYS);
        this.endDate = this.toIsoDate(today);
        this.startDate = this.toIsoDate(past);
    }

    toIsoDate(d) {
        return d.toISOString().slice(0, 10);
    }

    @wire(getCadenceOptions)
    wiredCadenceOptions({ data, error }) {
        this.isLoadingOptions = false;
        if (data) {
            this.allCadences = data;
            this.folderOptions = [...new Set(data.map((c) => c.folderName))]
                .sort()
                .map((f) => ({ label: f, value: f }));
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    get hasFolderSelected() {
        return !!this.selectedFolder;
    }

    get isFolderNotSelected() {
        return !this.selectedFolder;
    }

    get hasCadenceSelected() {
        return !!this.selectedCadenceId;
    }

    get hasAnyViewSelected() {
        return this.hasCadenceSelected || this.isAllCadencesView;
    }

    get isBusy() {
        return this.isLoadingData || this.isLoadingFolderMetrics;
    }

    get selectedFolderId() {
        const match = this.allCadences.find((c) => c.folderName === this.selectedFolder);
        return match ? match.folderId : undefined;
    }

    get cadenceListForFolder() {
        if (!this.selectedFolder) {
            return [];
        }
        const term = this.cadenceSearchTerm.toLowerCase();
        return this.allCadences
            .filter((c) => c.folderName === this.selectedFolder)
            .filter((c) => !term || c.name.toLowerCase().includes(term))
            .map((c) => ({
                ...c,
                itemClass:
                    !this.isAllCadencesView && c.cadenceId === this.selectedCadenceId
                        ? 'cadence-item cadence-item_selected'
                        : 'cadence-item'
            }));
    }

    get allCadencesItemClass() {
        return this.isAllCadencesView
            ? 'cadence-item cadence-item_all cadence-item_selected'
            : 'cadence-item cadence-item_all';
    }

    get selectedCadenceName() {
        const match = this.allCadences.find((c) => c.cadenceId === this.selectedCadenceId);
        return match ? match.name : '';
    }

    handleFolderChange(event) {
        this.selectedFolder = event.detail.value;
        this.selectedCadenceId = undefined;
        this.cadenceSearchTerm = '';
        this.dashboardData = undefined;
        this.isAllCadencesView = false;
        this.folderCadenceSummaries = [];
        this.barSearchTerm = '';
        this.showAllBars = false;
    }

    handleCadenceSearch(event) {
        this.cadenceSearchTerm = event.target.value;
    }

    handleCadenceSelect(event) {
        this.selectedCadenceId = event.currentTarget.dataset.id;
        this.isAllCadencesView = false;
        this.loadDashboardData();
    }

    handleShowAllCadences() {
        this.isAllCadencesView = true;
        this.selectedCadenceId = undefined;
        this.dashboardData = undefined;
        this.barSearchTerm = '';
        this.showAllBars = false;
        this.loadFolderMetrics();
    }

    handleBarClick(event) {
        this.selectedCadenceId = event.currentTarget.dataset.id;
        this.isAllCadencesView = false;
        this.loadDashboardData();
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
        if (this.isAllCadencesView) {
            this.loadFolderMetrics();
        } else {
            this.loadDashboardData();
        }
    }

    loadDashboardData() {
        if (!this.selectedCadenceId || !this.startDate || !this.endDate) {
            return;
        }
        this.isLoadingData = true;
        this.error = undefined;
        getDashboardData({
            cadenceId: this.selectedCadenceId,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => {
                this.dashboardData = result;
            })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.dashboardData = undefined;
            })
            .finally(() => {
                this.isLoadingData = false;
            });
    }

    loadFolderMetrics() {
        const folderId = this.selectedFolderId;
        if (!folderId || !this.startDate || !this.endDate) {
            return;
        }
        this.isLoadingFolderMetrics = true;
        this.error = undefined;
        getFolderCadenceMetrics({
            folderId,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => {
                this.folderCadenceSummaries = result;
            })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.folderCadenceSummaries = [];
            })
            .finally(() => {
                this.isLoadingFolderMetrics = false;
            });
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }

    get overview() {
        return this.dashboardData ? this.dashboardData.overview : null;
    }

    get openRingValue() {
        return this.overview ? this.overview.openRate : 0;
    }

    get clickRingValue() {
        return this.overview ? this.overview.clickRate : 0;
    }

    get byRep() {
        const rows = this.dashboardData ? this.dashboardData.byRep : [];
        return rows.map((r, idx) => ({ ...r, key: `${idx}-${r.repName}` }));
    }

    get hasByRep() {
        return this.byRep.length > 0;
    }

    get clickedContacts() {
        const rows = this.dashboardData ? this.dashboardData.clickedContacts : [];
        return rows.map((r, idx) => ({ ...r, key: `${idx}-${r.contactName}` }));
    }

    get hasClickedContacts() {
        return this.clickedContacts.length > 0;
    }

    get opensOverTime() {
        return this.dashboardData ? this.dashboardData.opensOverTime : [];
    }

    get hasOpensOverTime() {
        return this.opensOverTime.length > 0;
    }

    get lineChartViewBox() {
        return `0 0 ${CHART_WIDTH} ${CHART_HEIGHT}`;
    }

    get lineChartPoints() {
        const series = this.opensOverTime;
        if (!series.length) {
            return '';
        }
        const maxCount = Math.max(...series.map((p) => p.count));
        const stepX =
            series.length > 1 ? (CHART_WIDTH - CHART_PADDING * 2) / (series.length - 1) : 0;
        return series
            .map((point, index) => {
                const x = CHART_PADDING + stepX * index;
                const y =
                    maxCount > 0
                        ? CHART_HEIGHT -
                          CHART_PADDING -
                          (point.count / maxCount) * (CHART_HEIGHT - CHART_PADDING * 2)
                        : CHART_HEIGHT - CHART_PADDING;
                return `${x.toFixed(1)},${y.toFixed(1)}`;
            })
            .join(' ');
    }

    get chartRangeLabel() {
        const series = this.opensOverTime;
        if (!series.length) {
            return '';
        }
        return `${series[0].day} → ${series[series.length - 1].day}`;
    }

    get barMetricOptions() {
        return BAR_METRIC_OPTIONS;
    }

    get barMetricLabel() {
        const found = BAR_METRIC_OPTIONS.find((o) => o.value === this.selectedBarMetric);
        return found ? found.label : '';
    }

    get hasFolderCadenceSummaries() {
        return this.folderCadenceSummaries.length > 0;
    }

    get filteredFolderSummaries() {
        const term = this.barSearchTerm.toLowerCase().trim();
        if (!term) {
            return this.folderCadenceSummaries;
        }
        return this.folderCadenceSummaries.filter((s) => s.name.toLowerCase().includes(term));
    }

    get hasFilteredFolderSummaries() {
        return this.filteredFolderSummaries.length > 0;
    }

    get isBarListTruncated() {
        return (
            !this.showAllBars &&
            !this.barSearchTerm.trim() &&
            this.filteredFolderSummaries.length > BAR_CHART_DEFAULT_LIMIT
        );
    }

    get showAllBarsLabel() {
        return this.showAllBars
            ? 'Show top 20 only'
            : `Show all ${this.filteredFolderSummaries.length} cadences`;
    }

    get showToggleAllBarsButton() {
        return !this.barSearchTerm.trim() && this.filteredFolderSummaries.length > BAR_CHART_DEFAULT_LIMIT;
    }

    get barCountLabel() {
        const total = this.filteredFolderSummaries.length;
        const shown = this.folderBars.length;
        if (shown === total) {
            return `Showing all ${total} cadence${total === 1 ? '' : 's'}`;
        }
        return `Showing top ${shown} of ${total} cadences`;
    }

    get folderChartHeight() {
        return BAR_CHART_HEIGHT;
    }

    get folderChartWidth() {
        const count = this.folderBars.length;
        const width = BAR_GAP + count * (BAR_WIDTH + BAR_GAP);
        return Math.max(width, BAR_CHART_MIN_WIDTH);
    }

    get folderBars() {
        const summaries = this.filteredFolderSummaries;
        if (!summaries.length) {
            return [];
        }
        const metric = this.selectedBarMetric;
        const sorted = [...summaries].sort((a, b) => (b[metric] || 0) - (a[metric] || 0));
        const visible = this.isBarListTruncated ? sorted.slice(0, BAR_CHART_DEFAULT_LIMIT) : sorted;

        const baselineY = BAR_CHART_HEIGHT - BAR_CHART_BASELINE_PADDING;
        const availableHeight = baselineY - BAR_CHART_TOP_PADDING;
        const maxValue = Math.max(...visible.map((s) => s[metric] || 0), 0);

        return visible.map((s, index) => {
            const value = s[metric] || 0;
            const rawHeight = maxValue > 0 ? (value / maxValue) * availableHeight : 0;
            const height = value > 0 ? Math.max(rawHeight, 2) : 0;
            const x = BAR_GAP + index * (BAR_WIDTH + BAR_GAP);
            const nameX = x + BAR_WIDTH / 2;
            const nameY = baselineY + 14;
            const shortName = s.name.length > 16 ? `${s.name.slice(0, 15)}…` : s.name;
            return {
                key: s.cadenceId,
                cadenceId: s.cadenceId,
                name: s.name,
                shortName,
                value,
                displayValue: metric === 'sent' ? String(value) : `${value}%`,
                x,
                y: baselineY - height,
                width: BAR_WIDTH,
                height,
                labelY: Math.max(baselineY - height - 6, 10),
                nameX,
                nameY,
                nameTransform: `rotate(-40 ${nameX} ${nameY})`
            };
        });
    }
}
