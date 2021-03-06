/*
 * Copyright (c) 2014, 2019 Oracle and/or its affiliates. All rights reserved. This
 * code is released under a tri EPL/GPL/LGPL license. You can use it,
 * redistribute it and/or modify it under the terms of the:
 *
 * Eclipse Public License version 2.0, or
 * GNU General Public License version 2, or
 * GNU Lesser General Public License version 2.1.
 */
package org.truffleruby.core.array;

import org.truffleruby.Layouts;
import org.truffleruby.core.array.library.ArrayStoreLibrary;
import org.truffleruby.language.RubyContextNode;
import org.truffleruby.language.objects.AllocateObjectNode;

import com.oracle.truffle.api.CompilerDirectives;
import com.oracle.truffle.api.dsl.Cached;
import com.oracle.truffle.api.dsl.ImportStatic;
import com.oracle.truffle.api.dsl.Specialization;
import com.oracle.truffle.api.frame.VirtualFrame;
import com.oracle.truffle.api.library.CachedLibrary;
import com.oracle.truffle.api.nodes.ExplodeLoop;
import com.oracle.truffle.api.object.DynamicObject;

/** Dup an array, without using any method lookup. This isn't a call - it's an operation on a core class. */
@ImportStatic(ArrayGuards.class)
public abstract class ArrayDupNode extends RubyContextNode {

    @Child private AllocateObjectNode allocateNode;

    public abstract DynamicObject executeDup(VirtualFrame frame, DynamicObject array);

    @Specialization(
            guards = {
                    "getSize(from) == cachedSize",
                    "cachedSize <= ARRAY_MAX_EXPLODE_SIZE" },
            limit = "getCacheLimit()")
    protected DynamicObject dupProfiledSize(DynamicObject from,
            @CachedLibrary("getStore(from)") ArrayStoreLibrary fromStores,
            @CachedLibrary(limit = "1") ArrayStoreLibrary toStores,
            @Cached("getSize(from)") int cachedSize) {
        return copyArraySmall(fromStores, toStores, from, cachedSize);
    }

    @ExplodeLoop
    private DynamicObject copyArraySmall(ArrayStoreLibrary fromStores, ArrayStoreLibrary toStores,
            DynamicObject from, int cachedSize) {
        final Object original = Layouts.ARRAY.getStore(from);
        final Object copy = fromStores.allocator(original).allocate(cachedSize);
        for (int i = 0; i < cachedSize; i++) {
            toStores.write(copy, i, fromStores.read(original, i));
        }
        return allocateArray(coreLibrary().arrayClass, copy, cachedSize);
    }

    @Specialization(replaces = "dupProfiledSize")
    protected DynamicObject dup(DynamicObject from,
            @Cached ArrayCopyOnWriteNode cowNode) {
        final int size = Layouts.ARRAY.getSize(from);
        final Object copy = cowNode.execute(from, 0, Layouts.ARRAY.getSize(from));
        return allocateArray(coreLibrary().arrayClass, copy, size);
    }

    private DynamicObject allocateArray(DynamicObject arrayClass, Object store, int size) {
        if (allocateNode == null) {
            CompilerDirectives.transferToInterpreterAndInvalidate();
            allocateNode = insert(AllocateObjectNode.create());
        }
        return allocateNode.allocateArray(arrayClass, store, size);
    }

    protected int getCacheLimit() {
        return getContext().getOptions().ARRAY_DUP_CACHE;
    }

}
