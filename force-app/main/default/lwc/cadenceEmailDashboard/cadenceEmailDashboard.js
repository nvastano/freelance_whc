import { LightningElement, wire } from 'lwc';
import getCadenceOptions from '@salesforce/apex/CadenceEmailDashboardController.getCadenceOptions';
import getDashboardData from '@salesforce/apex/CadenceEmailDashboardController.getDashboardData';
import getDrillDownRecords from '@salesforce/apex/CadenceEmailDashboardController.getDrillDownRecords';

const CHART_WIDTH = 600;
const CHART_HEIGHT = 160;
const CHART_PADDING = 12;

const DRILL_LABELS = {
    sent: 'All Sent',
    delivered: 'Delivered',
    opened: 'Opened',
    clicked: 'Clicked',
    bounced: 'Bounced',
    replied: 'Replied'
};

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
    error;
    dashboardData;

    drillFilter = null;
    drillRepId = null;
    drillRepName = null;
    drillDownRecords = [];
    isLoadingDrill = false;
    drillError = null;

    connectedCallback() {
        const today = new Date();
        const past = new Date(today);
        past.setMonth(past.getMonth() - 1);
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

    get showCadenceList() {
        return !!this.cadenceSearchTerm || !!this.selectedFolder;
    }

    get cadenceListForFolder() {
        const term = this.cadenceSearchTerm.toLowerCase();
        return this.allCadences
            .filter((c) => !this.selectedFolder || c.folderName === this.selectedFolder)
            .filter((c) => !term || c.name.toLowerCase().includes(term) || c.folderName.toLowerCase().includes(term))
            .map((c) => ({
                ...c,
                itemClass:
                    c.cadenceId === this.selectedCadenceId
                        ? 'cadence-item cadence-item_selected'
                        : 'cadence-item',
                showFolder: !this.selectedFolder
            }));
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
        this.closeDrill();
    }

    handleCadenceSearch(event) {
        this.cadenceSearchTerm = event.target.value;
    }

    handleCadenceSelect(event) {
        this.selectedCadenceId = event.currentTarget.dataset.id;
        const match = this.allCadences.find((c) => c.cadenceId === this.selectedCadenceId);
        if (match) this.selectedFolder = match.folderName;
        this.cadenceSearchTerm = '';
        this.closeDrill();
        this.loadDashboardData();
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
        this.closeDrill();
        this.loadDashboardData();
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
        this.closeDrill();
        this.loadDashboardData();
    }

    loadDashboardData() {
        if (!this.selectedCadenceId || !this.startDate || !this.endDate) return;
        this.isLoadingData = true;
        this.error = undefined;
        getDashboardData({
            cadenceId: this.selectedCadenceId,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then((result) => { this.dashboardData = result; })
            .catch((err) => {
                this.error = this.extractErrorMessage(err);
                this.dashboardData = undefined;
            })
            .finally(() => { this.isLoadingData = false; });
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }

    // ---- KPI / overview ----

    get overview() {
        return this.dashboardData ? this.dashboardData.overview : null;
    }

    get openRingValue() {
        return this.overview ? this.overview.openRate : 0;
    }

    get clickRingValue() {
        return this.overview ? this.overview.clickRate : 0;
    }

    // ---- KPI tile classes (highlight the active drill filter) ----

    get sentTileClass() { return this._tileClass('sent'); }
    get deliveredTileClass() { return this._tileClass('delivered'); }
    get openedTileClass() { return this._tileClass('opened'); }
    get clickedTileClass() { return this._tileClass('clicked'); }
    get bouncedTileClass() { return this._tileClass('bounced'); }
    get repliedTileClass() { return this._tileClass('replied'); }

    _tileClass(filter) {
        const active = this.drillFilter === filter && !this.drillRepId;
        return `slds-col kpi-tile${active ? ' kpi-tile_active' : ''}`;
    }

    // ---- By rep ----

    get byRep() {
        const rows = this.dashboardData ? this.dashboardData.byRep : [];
        return rows.map((r, idx) => ({
            ...r,
            key: `${idx}-${r.repName}`,
            rowClass: this.drillFilter === 'rep' && this.drillRepId === r.repId
                ? 'rep-row rep-row_active'
                : 'rep-row'
        }));
    }

    get hasByRep() {
        return this.byRep.length > 0;
    }

    // ---- Clicked contacts ----

    get clickedContacts() {
        const rows = this.dashboardData ? this.dashboardData.clickedContacts : [];
        return rows.map((r, idx) => ({ ...r, key: `${idx}-${r.contactName}` }));
    }

    get hasClickedContacts() {
        return this.clickedContacts.length > 0;
    }

    // ---- Opens over time chart ----

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
        if (!series.length) return '';
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
        if (!series.length) return '';
        return `${series[0].day} → ${series[series.length - 1].day}`;
    }

    // ---- Drill-down ----

    get hasDrillDown() {
        return !!this.drillFilter;
    }

    get drillTitle() {
        if (this.drillFilter === 'rep') return `Records for ${this.drillRepName}`;
        return DRILL_LABELS[this.drillFilter] || 'Details';
    }

    get drillRows() {
        return this.drillDownRecords.map((r, idx) => ({
            ...r,
            key: `${idx}-${r.contactName}-${r.sentDate}`,
            openedLabel: r.isOpened ? '✓' : '—',
            openedClass: r.isOpened ? 'drill-check drill-check_yes' : 'drill-check',
            clickedLabel: r.isClicked ? '✓' : '—',
            clickedClass: r.isClicked ? 'drill-check drill-check_yes' : 'drill-check',
            bouncedLabel: r.isBounced ? '✓' : '—',
            bouncedClass: r.isBounced ? 'drill-check drill-check_warn' : 'drill-check',
            repliedLabel: r.hasReply ? '✓' : '—',
            repliedClass: r.hasReply ? 'drill-check drill-check_yes' : 'drill-check'
        }));
    }

    get hasDrillRows() {
        return this.drillRows.length > 0;
    }

    get drillRowCount() {
        const n = this.drillRows.length;
        return n === 500 ? 'Showing first 500 records' : `${n} record${n !== 1 ? 's' : ''}`;
    }

    handleKpiClick(event) {
        const filter = event.currentTarget.dataset.filter;
        if (this.drillFilter === filter && !this.drillRepId) {
            this.closeDrill();
            return;
        }
        this.drillFilter = filter;
        this.drillRepId = null;
        this.drillRepName = null;
        this.loadDrill();
    }

    handleRepRowClick(event) {
        const repId = event.currentTarget.dataset.repId;
        const repName = event.currentTarget.dataset.repName;
        if (this.drillFilter === 'rep' && this.drillRepId === repId) {
            this.closeDrill();
            return;
        }
        this.drillFilter = 'rep';
        this.drillRepId = repId;
        this.drillRepName = repName;
        this.loadDrill();
    }

    closeDrill() {
        this.drillFilter = null;
        this.drillRepId = null;
        this.drillRepName = null;
        this.drillDownRecords = [];
        this.drillError = null;
    }

    loadDrill() {
        if (!this.selectedCadenceId || !this.startDate || !this.endDate || !this.drillFilter) return;
        this.isLoadingDrill = true;
        this.drillError = null;
        this.drillDownRecords = [];
        getDrillDownRecords({
            cadenceId: this.selectedCadenceId,
            startDate: this.startDate,
            endDate: this.endDate,
            filterType: this.drillFilter,
            repId: this.drillRepId || null
        })
            .then((result) => { this.drillDownRecords = result; })
            .catch((err) => { this.drillError = this.extractErrorMessage(err); })
            .finally(() => { this.isLoadingDrill = false; });
    }
}
