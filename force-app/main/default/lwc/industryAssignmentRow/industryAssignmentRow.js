import { LightningElement, api, track } from 'lwc';

export default class IndustryAssignmentRow extends LightningElement {
    @api primaryIndustryOptions = [];
    @api subIndustryOptions = [];
    @api usedSubIndustries = [];   // array of already-used sub-industry values
    @api groupOptions = [];
    @api ltMemberOptions = [];
    @api isNew = false;
    @api selected = false;

    @track editing = false;
    @track draft = {};
    @track saveError = null;
    _record = {};

    @api
    get record() {
        return this._record;
    }
    set record(val) {
        this._record = val || {};
        // If new row, start in edit mode immediately
        if (this.isNew) {
            this.editing = true;
            this.draft = { ...this._record };
        }
    }

    connectedCallback() {
        if (this.isNew) {
            this.editing = true;
            this.draft = { ...this._record };
        }
    }

    // ── Read-only display values ─────────────────────────────────────────────
    get displaySubIndustry()   { return this._record.ZI_Sub_Industry__c   || '—'; }
    get displayPrimary()       { return this._record.ZI_Primary_Industry__c || '—'; }
    get displayGroup()         { return this._record.Assignment_Group__r?.Name || '—'; }
    get displayMember()        { return this._record.LT_Member__r?.Name    || '—'; }
    get isActive()             { return this._record.Active__c; }
    get activeLabel()          { return this._record.Active__c ? 'Active' : 'Inactive'; }
    get activeClass()          { return this._record.Active__c
        ? 'slds-badge slds-badge_success'
        : 'slds-badge'; }

    get isReadMode()  { return !this.editing; }
    get isEditMode()  { return this.editing; }

    // Sub-industry options for edit mode:
    // exclude already-used values, but always include this record's own current value
    get filteredSubOptions() {
        const ownValue = this._record.ZI_Sub_Industry__c;
        const usedSet = new Set(this.usedSubIndustries);
        return this.subIndustryOptions.filter(o => !usedSet.has(o.value) || o.value === ownValue);
    }

    // ── Edit handlers ────────────────────────────────────────────────────────
    handleEdit() {
        this.draft = { ...this._record };
        this.editing = true;
    }

    handleCancel() {
        if (this.isNew) {
            this.dispatchEvent(new CustomEvent('cancel'));
        } else {
            this.editing = false;
        }
    }

    handleFieldChange(e) {
        const field = e.target.dataset.field;
        const value = e.target.type === 'checkbox' ? e.target.checked : e.detail.value;
        this.draft = { ...this.draft, [field]: value };
    }

    handleSave() {
        this.saveError = null;
        this.dispatchEvent(new CustomEvent('save', { detail: { ...this.draft } }));
        if (!this.isNew) {
            this._record = { ...this._record, ...this.draft };
            this.editing = false;
        }
    }

    handleCheckbox(e) {
        this.dispatchEvent(new CustomEvent('rowselect', {
            detail: { recordId: this._record.Id, selected: e.target.checked }
        }));
    }

    handleDelete() {
        // eslint-disable-next-line no-alert
        if (window.confirm(`Delete "${this._record.ZI_Sub_Industry__c}"?`)) {
            this.dispatchEvent(new CustomEvent('delete', { detail: this._record.Id }));
        }
    }
}