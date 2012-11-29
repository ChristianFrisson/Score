/*
	 Jamoma Class for representing parameters for modules, plug-ins, etc.
	 Copyright © 2010 by Timothy Place
	 
	 License: This code is licensed under the terms of the "New BSD License"
	 http://creativecommons.org/licenses/BSD/
*/

#ifndef __TT_PARAMETER_H__
#define __TT_PARAMETER_H__

#include "TTBase.h"


class TTFOUNDATION_EXPORT TTParameter : public TTDataObject {
	TTCLASS_SETUP(TTParameter)
	
public:
	TTGraphObjectPtr	mOwner;
	TTSymbol			mName;
	TTFloat64			mRangeBottom;
	TTFloat64			mRangeTop;
	TTFloat64			mDefault;
	TTSymbol			mStyle;
	TTFloat64			mValue;
	TTDictionary		mDictionary;
	
	// attribute accessors
	TTErr setName(const TTValue& newValue);
	TTErr setValue(const TTValue& newValue);

	// graph stuff
	TTErr setOwner(TTGraphObjectPtr newOwner);
	TTErr push(const TTDictionary& aDictionary);
};

typedef TTParameter* TTParameterPtr;


#endif // __TT_PARAMETER_H__
