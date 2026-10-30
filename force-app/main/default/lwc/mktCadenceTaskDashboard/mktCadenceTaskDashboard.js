import { LightningElement, wire } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import getUserOptions from '@salesforce/apex/MktCadenceTaskDashboardController.getUserOptions';
import getCadenceOptions from '@salesforce/apex/MktCadenceTaskDashboardController.getCadenceOptions';
import getDashboardData from '@salesforce/apex/MktCadenceTaskDashboardController.getDashboardData';

const ALL_USERS_VALUE = '';
const ALL_CADENCES_VALUE = '';

export default class MktCadenceTaskDashboard extends LightningElement {
    currentUserId = USER_ID;
    userOptionsList = [];
    cadenceOptionsList = [];
    selectedOwnerId = ALL_USERS_VALUE;
    selectedCadenceId = ALL_CADENCES_VALUE;
    searchTerm = '';
    isLoadingOptions = true;
    isLoadingCadenceOptions = true;
    isLoadingData = true;
    error;
    accountRows = [];
    _defaultApplied = false;
    selectedKpiFilter;

    @wire(getUserOptions)
    wiredUserOptions({ data, error }) {
        this.isLoadingOptions = false;
        if (data) {
            this.userOptionsList = data.map((o) => ({ label: o.name, value: o.userId }));
            if (!this._defaultApplied) {
                this._defaultApplied = true;
                const mine = data.find((o) => o.userId === this.currentUserId);
                if (mine) {
                    this.selectedOwnerId = mine.userId;
                }
            }
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    @wire(getCadenceOptions)
    wiredCadenceOptions({ data, error }) {
        this.isLoadingCadenceOptions = false;
        if (data) {
            this.cadenceOptionsList = data.map((o) => ({ label: o.name, value: o.cadenceId }));
        } else if (error) {
            this.error = this.extractErrorMessage(error);
        }
    }

    @wire(getDashboardData, { ownerId: '$ownerIdParam', cadenceId: '$cadenceIdParam' })
    wiredDashboardData({ data, error }) {
        this.isLoadingData = false;
        if (data) {
            this.accountRows = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.extractErrorMessage(error);
            this.accountRows = [];
        }
    }

    get ownerIdParam() {
        return this.selectedOwnerId || null;
    }

    get cadenceIdParam() {
        return this.selectedCadenceId || null;
    }

    get userFilterOptions() {
        return [{ label: 'All Users', value: ALL_USERS_VALUE }, ...this.userOptionsList];
    }

    get cadenceFilterOptions() {
        return [{ label: 'All Cadences', value: ALL_CADENCES_VALUE }, ...this.cadenceOptionsList];
    }

    get isLoading() {
        return this.isLoadingOptions || this.isLoadingCadenceOptions || this.isLoadingData;
    }

    handleOwnerChange(event) {
        this.selectedOwnerId = event.detail.value;
    }

    handleCadenceChange(event) {
        this.selectedCadenceId = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    get matchingRows() {
        const term = this.searchTerm.toLowerCase().trim();
        return !term
            ? this.accountRows
            : this.accountRows.filter((r) => r.accountName.toLowerCase().includes(term));
    }

    handleKpiClick(event) {
        const filter = event.currentTarget.dataset.filter;
        this.selectedKpiFilter = this.selectedKpiFilter === filter ? undefined : filter;
    }

    handleClearKpiFilter() {
        this.selectedKpiFilter = undefined;
    }

    get kpiFilteredRows() {
        switch (this.selectedKpiFilter) {
            case 'running':
                return this.matchingRows.filter((r) => r.activeCadences.length > 0);
            case 'awaiting':
                return this.matchingRows.filter(
                    (r) => r.activeCadences.length === 0 && r.followUpTasks.length > 0
                );
            case 'pendingFollowUps':
                return this.matchingRows.filter((r) => r.followUpTasks.length > 0);
            case 'newIntent':
                return this.matchingRows.filter((r) => r.newIntentSignals.length > 0);
            default:
                return this.matchingRows;
        }
    }

    get filteredRows() {
        return this.kpiFilteredRows.map((r) => this.decorateRow(r));
    }

    get hasKpiFilter() {
        return !!this.selectedKpiFilter;
    }

    get runningTileClass() {
        return this.kpiTileClass('running');
    }

    get awaitingTileClass() {
        return this.kpiTileClass('awaiting');
    }

    get pendingFollowUpTileClass() {
        return this.kpiTileClass('pendingFollowUps');
    }

    get newIntentTileClass() {
        return this.kpiTileClass('newIntent');
    }

    kpiTileClass(filter) {
        return this.selectedKpiFilter === filter ? 'kpi-tile kpi-tile_selected' : 'kpi-tile';
    }

    decorateRow(row) {
        const hasNewIntent = row.newIntentSignals.length > 0;
        return {
            accountId: row.accountId,
            accountName: row.accountName,
            accountUrl: `/lightning/r/Account/${row.accountId}/view`,
            hasNewIntent,
            newIntentTooltip: hasNewIntent
                ? row.newIntentSignals
                      .map(
                          (s) =>
                              `${s.topic} (score ${s.surgeScore}, ${s.signalDate})${
                                  s.suggestedCadenceName ? ' → ' + s.suggestedCadenceName : ''
                              }`
                      )
                      .join('\n')
                : '',
            activeCadenceLines: row.activeCadences.map((c, idx) => ({
                key: `${row.accountId}-ac-${idx}`,
                text: `${c.cadenceName} — ${c.contactName}`
            })),
            followUpLines: row.followUpTasks.map((t, idx) => ({
                key: `${row.accountId}-fu-${idx}`,
                text: `${t.subject} — ${t.contactName}${t.dueDate ? ' (due ' + t.dueDate + ')' : ''}`
            }))
        };
    }

    // Rendered directly in the template as a real <a href=... download> element instead of
    // being built and .click()'d from JS - a synthetic click on a JS-created anchor is
    // unreliable under Lightning's DOM sandboxing (silently does nothing in some contexts),
    // while a real template-rendered anchor the user actually clicks always works.
    get exportCsvHref() {
        if (!this.hasExportableIntents) {
            return undefined;
        }
        const header = ['Account', 'Topic', 'Category', 'Surge Score', 'Signal Date', 'Suggested Cadence'];
        const lines = [header.map((h) => this.csvEscape(h)).join(',')];

        this.kpiFilteredRows.forEach((row) => {
            row.newIntentSignals.forEach((s) => {
                lines.push(
                    [
                        row.accountName,
                        s.topic,
                        s.category,
                        s.surgeScore,
                        s.signalDate,
                        s.suggestedCadenceName || ''
                    ]
                        .map((v) => this.csvEscape(v))
                        .join(',')
                );
            });
        });

        const csvContent = lines.join('\r\n');
        return 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvContent);
    }

    get exportCsvFileName() {
        return `mkt_new_intent_signals_${new Date().toISOString().slice(0, 10)}.csv`;
    }

    csvEscape(value) {
        const str = value === null || value === undefined ? '' : String(value);
        return `"${str.replace(/"/g, '""')}"`;
    }

    get newIntentCount() {
        return this.matchingRows.filter((r) => r.newIntentSignals.length > 0).length;
    }

    get hasExportableIntents() {
        return this.kpiFilteredRows.some((r) => r.newIntentSignals.length > 0);
    }

    get activelyRunningCount() {
        return this.matchingRows.filter((r) => r.activeCadences.length > 0).length;
    }

    get awaitingFollowUpOnlyCount() {
        return this.matchingRows.filter((r) => r.activeCadences.length === 0 && r.followUpTasks.length > 0)
            .length;
    }

    get hasRows() {
        return this.matchingRows.length > 0;
    }

    get hasFilteredRows() {
        return this.filteredRows.length > 0;
    }

    get isEmptyState() {
        return !this.isLoading && !this.error && !this.hasRows;
    }

    get isKpiFilterEmptyState() {
        return this.hasRows && this.hasKpiFilter && !this.hasFilteredRows;
    }

    get pendingFollowUpCount() {
        return this.matchingRows.reduce((sum, r) => sum + r.followUpTasks.length, 0);
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }
}
