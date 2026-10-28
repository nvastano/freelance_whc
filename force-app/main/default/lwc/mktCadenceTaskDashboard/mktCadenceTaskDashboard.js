import { LightningElement, wire } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import getUserOptions from '@salesforce/apex/MktCadenceTaskDashboardController.getUserOptions';
import getDashboardData from '@salesforce/apex/MktCadenceTaskDashboardController.getDashboardData';

const ALL_USERS_VALUE = '';

export default class MktCadenceTaskDashboard extends LightningElement {
    currentUserId = USER_ID;
    userOptionsList = [];
    selectedOwnerId = ALL_USERS_VALUE;
    searchTerm = '';
    isLoadingOptions = true;
    isLoadingData = true;
    error;
    accountRows = [];
    _defaultApplied = false;

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

    @wire(getDashboardData, { ownerId: '$ownerIdParam' })
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

    get userFilterOptions() {
        return [{ label: 'All Users', value: ALL_USERS_VALUE }, ...this.userOptionsList];
    }

    get isLoading() {
        return this.isLoadingOptions || this.isLoadingData;
    }

    handleOwnerChange(event) {
        this.selectedOwnerId = event.detail.value;
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

    get filteredRows() {
        return this.matchingRows.map((r) => this.decorateRow(r));
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

    handleExportIntents() {
        const header = ['Account', 'Topic', 'Category', 'Surge Score', 'Signal Date', 'Suggested Cadence'];
        const lines = [header.map((h) => this.csvEscape(h)).join(',')];

        this.matchingRows.forEach((row) => {
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
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `mkt_new_intent_signals_${new Date().toISOString().slice(0, 10)}.csv`;
        link.click();
        URL.revokeObjectURL(url);
    }

    csvEscape(value) {
        const str = value === null || value === undefined ? '' : String(value);
        return `"${str.replace(/"/g, '""')}"`;
    }

    get newIntentCount() {
        return this.accountRows.filter((r) => r.newIntentSignals.length > 0).length;
    }

    get hasExportableIntents() {
        return this.matchingRows.some((r) => r.newIntentSignals.length > 0);
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    get isEmptyState() {
        return !this.isLoading && !this.error && !this.hasRows;
    }

    get rowCountLabel() {
        return String(this.filteredRows.length);
    }

    get pendingFollowUpCount() {
        return this.accountRows.reduce((sum, r) => sum + r.followUpTasks.length, 0);
    }

    extractErrorMessage(error) {
        return (error && error.body && error.body.message) || 'An unknown error occurred.';
    }
}
