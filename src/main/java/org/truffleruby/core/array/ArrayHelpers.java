/*
 * Copyright (c) 2016, 2019 Oracle and/or its affiliates. All rights reserved. This
 * code is released under a tri EPL/GPL/LGPL license. You can use it,
 * redistribute it and/or modify it under the terms of the:
 *
 * Eclipse Public License version 2.0, or
 * GNU General Public License version 2, or
 * GNU Lesser General Public License version 2.1.
 */
package org.truffleruby.core.array;

import org.truffleruby.Layouts;
import org.truffleruby.RubyContext;
import org.truffleruby.core.array.library.ArrayStoreLibrary;

import com.oracle.truffle.api.object.DynamicObject;

public abstract class ArrayHelpers {

    public static Object getStore(DynamicObject array) {
        return Layouts.ARRAY.getStore(array);
    }

    public static int getSize(DynamicObject array) {
        return Layouts.ARRAY.getSize(array);
    }

    public static void setStoreAndSize(DynamicObject array, Object store, int size) {
        Layouts.ARRAY.setStore(array, store);
        setSize(array, size);
    }

    /** Sets the size of the given array
     *
     * Asserts that the size is valid for the current store of the array. If setting both size and store, use
     * setStoreAndSize or be sure to setStore before setSize as this assertion may fail.
     * 
     * @param array
     * @param size */
    public static void setSize(DynamicObject array, int size) {
        assert ArrayOperations.getStoreCapacity(array) >= size;
        Layouts.ARRAY.setSize(array, size);
    }

    public static DynamicObject createArray(RubyContext context, Object store, int size) {
        assert !(store instanceof Object[]) || store.getClass() == Object[].class;
        return Layouts.ARRAY.createArray(context.getCoreLibrary().arrayFactory, store, size);
    }

    public static DynamicObject createArray(RubyContext context, int[] store) {
        return createArray(context, store, store.length);
    }

    public static DynamicObject createArray(RubyContext context, long[] store) {
        return createArray(context, store, store.length);
    }

    public static DynamicObject createArray(RubyContext context, Object[] store) {
        assert store.getClass() == Object[].class;
        return createArray(context, store, store.length);
    }

    public static DynamicObject createEmptyArray(RubyContext context) {
        return Layouts.ARRAY.createArray(context.getCoreLibrary().arrayFactory, ArrayStoreLibrary.INITIAL_STORE, 0);
    }

    /** Returns a Java array of the narrowest possible type holding {@code object}. */
    public static Object specializedJavaArrayOf(ArrayBuilderNode builder, Object object) {
        final ArrayBuilderNode.BuilderState state = builder.start();
        builder.appendValue(state, 0, object);
        return builder.finish(state, 1);
    }

    /** Returns a Java array of the narrowest possible type holding the {@code objects}. */
    public static Object specializedJavaArrayOf(ArrayBuilderNode builder, Object... objects) {
        final ArrayBuilderNode.BuilderState state = builder.start();
        for (Object object : objects) {
            builder.appendValue(state, 0, object);
        }
        return builder.finish(state, objects.length);
    }

    /** Returns a Ruby array backed by a store of the narrowest possible type, holding {@code object}. */
    public static DynamicObject specializedRubyArrayOf(RubyContext context, ArrayBuilderNode builder, Object object) {
        return createArray(context, specializedJavaArrayOf(builder, object), 1);
    }

    /** Returns a Ruby array backed by a store of the narrowest possible type, holding the {@code objects}. */
    public static DynamicObject specializedRubyArrayOf(RubyContext context, ArrayBuilderNode builder,
            Object... objects) {
        return createArray(context, specializedJavaArrayOf(builder, objects), objects.length);
    }

}
