defmodule Streaming.StreamController do
  use Streaming.Web, :controller
  alias Streaming.Auth
  alias Streaming.Auth.User
  alias Streaming.Auth.Guardian
  alias Streaming.Stream

  defp get_thumbnails(rtsp_url,stream_name) do
    Porcelain.shell("ffmpeg -i #{rtsp_url} -r 1 -an -frames 1  -updatefirst 1 -y web/static/assets/images/#{stream_name}.jpg")


  end




  defp ffmpeg_pids(rtsp_url) do
    Porcelain.shell("ps -ef | grep ffmpeg | grep '#{rtsp_url}' | grep -v grep | awk '{print $2}'").out
    |> String.split
  end


def player(conn, %{ "stream" => stream, "action" => action}) do

  case action do
     "play" -> play(conn, stream)
     "stop" -> stop(conn, stream)
  end

end

  def play(conn, stream) do
  stream_db= Repo.get(Stream, stream)
  case stream_db.status do
    "offline" ->
      %{source: source}=stream_db
      %{output: output}=stream_db
      pid=spawn (fn ->     start_stream(source,output,stream_db.title)      end)
      stream_pid=String.to_atom("pid_#{stream_db.id}")
      Process.register(pid, stream_pid)
      changeset= Stream.changeset_play_pause(stream_db, %{"ffmpeg_pid" => "#{stream_pid}" , "status" => "online"})

      case Repo.update(changeset) do
        {:ok, _Stream}  ->
            redirect(put_flash(conn, :info, "Stream online"), to: stream_path(conn, :index ))
        {:error, changeset} ->
          redirect(put_flash(conn, :error , "Failed putting stream online"), to: stream_path(conn, :index))
        end

          "online" ->
          redirect(put_flash(conn, :info, "Stream already online !"), to: stream_path(conn, :index ))

  end


  end

  def stop(conn, stream) do
    stream_db= Repo.get(Stream, stream)

    case stream_db.status do
      "online" ->

      stream_pid=String.to_atom("pid_#{stream_db.id}")

     :erlang.whereis(stream_pid)
      %{source: source}=stream_db
      %{output: output}=stream_db
      Process.exit(:erlang.whereis(stream_pid), :kill)
    source_list=  ffmpeg_pids(source)
    output_list=  ffmpeg_pids(output)
      diff_list=source_list -- output_list
      common_list=source_list -- diff_list
      Enum.each(common_list, fn ffmpeg_process ->    System.cmd("kill",["-9"," #{ffmpeg_process}"]) end)

        changeset= Stream.changeset_play_pause(stream_db, %{"ffmpeg_pid" => "null" , "status" => "offline"})

        case Repo.update(changeset) do
          {:ok, _Stream}  ->
              redirect(put_flash(conn, :info, "Stream set offline "), to: stream_path(conn, :index ))
          {:error, changeset} ->
            redirect(put_flash(conn, :error , "Failed putting stream offline"), to: stream_path(conn, :index))
          end
            "offline" ->
            redirect(put_flash(conn, :info, "Stream already offline !"), to: stream_path(conn, :index ))

  end
end



  def start_stream(source, output,stream_name) do

    get_thumbnails(source,stream_name)
    command= "nohup nice -n -10  ffmpeg   -f  lavfi -i anullsrc -rtsp_transport tcp -i  #{source} -crf 10  -deinterlace -vcodec libx264 -pix_fmt yuv420 -b:v 2500k   -tune zerolatency   -c:v  copy   -s 854x480  -framerate 30 -g 2   -threads 2   -f flv #{output}"
    commandlist= String.split("#{command}")
    port =Port.open({:spawn, "#{command}"}, [:binary] )
        {:os_pid, pid} = Port.info(port, :os_pid)
    Process.sleep(600000);
    System.cmd("kill",["-9"," #{pid}"])
    start_stream(source,output,stream_name)

  end

  def index(conn, _params) do
    changeset = Auth.change_user(%User{})
    maybe_user = Guardian.Plug.current_resource(conn)
    message = if maybe_user != nil do
      "you are logged in"
    else
      "you are logged out"
    end
    streams = Repo.all(Stream)

    conn
    |> put_flash(:info, message)
    |> render("index.html", changeset: changeset, action: stream_path(conn, :login), maybe_user: maybe_user, streams: streams)
    #render conn, "index.html", Streams: Streams
  end

  def login(conn, %{"user" => %{"username" => username, "password" => password}}) do
     Auth.authenticate_user(username, password)
     |> login_reply(conn)
   end
   defp login_reply({:error, error}, conn) do
     conn
     |> put_flash(:error, error)
     |> redirect(to: "/")
   end
   defp login_reply({:ok, user}, conn) do
     conn
     |> put_flash(:success, "Welcome back!")
     |> Guardian.Plug.sign_in(user)
     |> redirect(to: "/")
   end
   def logout(conn, _) do
     conn
     |> Guardian.Plug.sign_out()
     |> redirect(to: stream_path(conn, :login))
   end





  def new(conn,params) do

    changeset=Stream.changeset(%Stream{},%{})

    render conn, "new.html", changeset: changeset
  end

def create(conn, %{"stream" => stream}) do
  changeset=Stream.changeset(%Stream{}, stream)

  case Repo.insert(changeset) do
    {:ok, stream_meta} ->
    old_Stream= Repo.get(Stream, stream_meta.id)
    %{source: source}=old_Stream
    %{output: output}=old_Stream
    pid=spawn (fn ->     start_stream(source,output,old_Stream.title)      end)
    source_list=ffmpeg_pids(source)
    output_list=ffmpeg_pids(output)
    diff_list=source_list -- output_list
    common_list=source_list -- diff_list

    stream_pid=String.to_atom("pid_#{old_Stream.id}")
   Process.register(pid, stream_pid)

    changeset_ffmpeg= Stream.changeset_ffmpeg(old_Stream, %{"ffmpeg_pid" => "#{stream_pid}", "status" => "online" })
    case Repo.update(changeset_ffmpeg) do
      {:ok, _Stream}  ->
          redirect(put_flash(conn, :info, "ffmpeg_pid Updated"), to: stream_path(conn, :index ))
     {:error, changeset} ->
      redirect(put_flash(conn, :error , "ffmpeg_pid update fail"), to: stream_path(conn, :index))
    end
      redirect(put_flash(conn,:info,"Stream Created"), to: stream_path(conn,:index) )


      render conn, "new.html", changeset: changeset
  end
end

def edit(conn, %{"id" => stream_id}) do
  stream= Repo.get(Stream, stream_id)
  changeset= Stream.changeset(stream)
  render conn, "edit.html", changeset: changeset, stream: stream
end

def update(conn, %{"id" => Stream_id, "Stream" => Stream}) do
  old_Stream= Repo.get(Stream, Stream_id)
  changeset= Stream.changeset(old_Stream, Stream)

  case Repo.update(changeset) do
    {:ok, _Stream}  ->
        redirect(put_flash(conn, :info, "Stream Updated"), to: stream_path(conn, :index ))
    {:error, changeset} ->
      redirect(put_flash(conn, :error , "error"), to: stream_path(conn, :edit, Stream_id))
  end
end

end
