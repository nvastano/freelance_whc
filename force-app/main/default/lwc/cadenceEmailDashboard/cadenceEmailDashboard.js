import { LightningElement, wire } from 'lwc';
import getCadenceOptions from '@salesforce/apex/CadenceEmailDashboardController.getCadenceOptions';
import getDashboardData from '@salesforce/apex/CadenceEmailDashboardController.getDashboardData';

const DEFAULT_RANGE_DAYS = 30;
const CHART_WIDTH = 600;
const CHART_HEIGHT = 160;
const CHART_PADDING = 12;

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
                    c.cadenceId === this.selectedCadenceId
                        ? 'cadence-item cadence-item_selected'
                        : 'cadence-item'
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
    }

    handleCadenceSearch(event) {
        this.cadenceSearchTerm = event.target.value;
    }

    handleCadenceSelect(event) {
        this.selectedCadenceId = event.currentTarget.dataset.id;
        this.loadDashboardData();
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
        this.loadDashboardData();
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
        this.loadDashboardData();
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
}
