public type SolrCollectionResponse record {|
    SolrResponseHeader responseHeader;
    string[] collections;
|};

public type SolrResponseHeader record {|
    boolean zkConnected = false;
    int status;
    int QTime;
    json params = {};
|};

public type SolrFieldsResponse record {|
    SolrResponseHeader responseHeader;
    SolrField[] fields;
|};

public type SolrField record {|
    string name;
    string 'type;
    boolean multiValued = false;
    boolean indexed = false;
    boolean stored = false;
    boolean docValues = false;
    boolean required = false;
|};

public type SolrCopyFieldsResponse record {|
    SolrResponseHeader responseHeader;
    SolrCopyField[] copyFields;
|};

public type SolrCopyField record {|
    string 'source;
    string dest;
|};

public type SolrFieldTypesResponse record {|
    SolrResponseHeader responseHeader;
    SolrFieldType[] fieldTypes;
|};

public type SolrFieldType record {
    string name;
    string 'class;
};



