
# PostgresqlSession is a down to the bare metal session store
# implementation to be used with +SmartSession+. It is much faster
# than the default ActiveRecord implementation.
#
# The implementation assumes that the table column names are 'id',
# 'session_id', 'data', 'created_at' and 'updated_at'. If you want use
# other names, you will need to change the SQL statments in the code.
#
# This table layout is compatible with ActiveRecordStore.

module SmartSession
  class PostgresqlSession

    attr_accessor :id, :session_id, :data, :lock_version

    def initialize(session_id, data)
      @session_id = session_id
      @quoted_session_id = self.class.session_connection.quote(session_id)
      @data = data
      @id = nil
      @lock_version = 0
    end

    class << self
      # retrieve the session table connection
      def session_connection
        SmartSession::SqlSession.connection
      end
      

      # try to find a session with a given +session_id+. returns nil if
      # no such session exists. note that we don't retrieve
      # +created_at+ and +updated_at+ as they are not accessed anywhyere
      # outside this class.
      
      def find_session(session_id, lock = false)
        connection = session_connection
        find("session_id=#{connection.quote session_id} LIMIT 1" + (lock ? ' FOR UPDATE' : ''))
      end
      
      def find_by_primary_id(primary_key_id, lock = false)
        if primary_key_id
          find("id='#{primary_key_id}'" + (lock ? ' FOR UPDATE' : ''))
        else
          nil
        end
      end
      
      def find(conditions)
        connection = session_connection
        result = connection.query("SELECT session_id, data,id #{  SmartSession::SqlSession.locking_enabled? ? ',lock_version ' : ''} FROM #{SmartSession::SqlSession.table_name} WHERE " + conditions)
        my_session = nil
        expected_columns = SmartSession::SqlSession.locking_enabled? ? 4 : 3
        
        if result[0] && result[0].size == expected_columns
         my_session = new(result[0][0], result[0][1])
          my_session.id = result[0][2]
          my_session.lock_version = result[0][3].to_i
        end
        result.clear
        my_session
      end
      
      # create a new session with given +session_id+ and +data+
      # and save it immediately to the database
      def create_session(session_id, data)
        new_session = new(session_id, data)
      end

      # delete all sessions meeting a given +condition+. it is the
      # caller's responsibility to pass a valid sql condition
      def delete_all(condition=nil)
        if condition
          session_connection.execute("DELETE FROM #{SmartSession::SqlSession.table_name} WHERE #{condition}")
        else
          session_connection.execute("DELETE FROM #{SmartSession::SqlSession.table_name}")
        end
      end

    end # class methods

    # update session with given +data+.
    # unlike the default implementation using ActiveRecord, updating of
    # column `updated_at` will be done by the database itself
    def update_session(data)
      connection = self.class.session_connection
      quoted_data = connection.quote(data)

      if @id
        # if @id is not nil, this is a session already stored in the database
        # update the relevant field using @id as key
        if SmartSession::SqlSession.locking_enabled?
          connection.execute("UPDATE #{SmartSession::SqlSession.table_name} SET \"updated_at\"=NOW(), \"data\"=#{quoted_data}, lock_version=lock_version+1 WHERE id=#{@id}")
          @lock_version += 1 #if we are here then we hold a lock on the table - we know our version is up to date
        else
          connection.execute("UPDATE #{SmartSession::SqlSession.table_name} SET \"updated_at\"=NOW(), \"data\"=#{quoted_data} WHERE id=#{@id}")
        end  
      else
        # if @id is nil, we need to create a new session in the database
        # and set @id to the primary key of the inserted record
        connection.execute("INSERT INTO #{SmartSession::SqlSession.table_name} (\"created_at\", \"updated_at\", \"session_id\", \"data\") VALUES (NOW(), NOW(), #{@quoted_session_id}, #{quoted_data})")
        @id = connection.lastval rescue connection.query("select lastval()")[0][0].to_i
        @lock_version = 0
      end
    end


    def update_session_optimistically(data)
      raise 'cannot update unsaved record optimistically' unless @id
      connection = self.class.session_connection
      quoted_data = connection.quote(data)
      result = connection.execute("UPDATE #{SmartSession::SqlSession.table_name} SET \"updated_at\"=NOW(), \"data\"=#{quoted_data}, lock_version=lock_version+1 WHERE id=#{@id} AND lock_version=#{@lock_version}")
      if  (result.class == Fixnum and result == 1) or  (result.class != Fixnum and result.cmd_tuples == 1)
        @lock_version += 1
        true
      else
        false
      end
    end
    # destroy the current session
    def destroy
      self.class.delete_all("session_id=#{@quoted_session_id}")
    end

  end
end

__END__

# This software is released under the MIT license
#
# Copyright (c) 2006 Stefan Kaes
# Copyright (c) 2007 Frederick Cheung

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
